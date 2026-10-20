"""lab-console collector: snapshot host status into /run/lab-console/status.json.

Runs as root from lab-console-collect.service. Every probe is bounded by a
timeout and reports {"error": ...} instead of raising. The output holds no
secrets: no environment, no tokens, only names, states, counts and times.
"""

import json
import os
import re
import shutil
import subprocess
import time

OUT_DIR = os.environ.get("LAB_CONSOLE_DIR", "/run/lab-console")
OUT = os.path.join(OUT_DIR, "status.json")
REPO = "/etc/nixos/bandit-nix"
TIMEOUT = 8

UNITS = [
    "traefik.service",
    "cloudflared-tunnel-bandit-lab.service",
    "docker-vaultwarden.service",
    "docker.service",
    "tailscaled.service",
    "crowdsec.service",
    "lab-update-apply.service",
]
BACKUP_TIMERS = {
    "lab": ("restic-backups-lab.timer", "restic-backups-lab.service"),
    "peer": ("restic-backups-peer.timer", "restic-backups-peer.service"),
}


def run(args, timeout=TIMEOUT):
    p = subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=timeout,
        stdin=subprocess.DEVNULL,
    )
    if p.returncode != 0:
        raise RuntimeError(f"{args[0]} exit {p.returncode}: {p.stderr.strip()[:160]}")
    return p.stdout


def probe(fn):
    try:
        return fn()
    except FileNotFoundError as e:
        return {"error": f"unavailable: {e.filename or e}"}
    except subprocess.TimeoutExpired:
        return {"error": "timeout"}
    except Exception as e:  # noqa: BLE001 - a probe must never kill the snapshot
        return {"error": str(e)[:200]}


def read(path):
    with open(path) as f:
        return f.read().strip()


def host():
    up = float(read("/proc/uptime").split()[0])
    load = [float(x) for x in read("/proc/loadavg").split()[:3]]
    return {
        "hostname": os.uname().nodename,
        "uptime_s": int(up),
        "load": load,
        "cpus": os.cpu_count(),
    }


def memory():
    info = {}
    for line in read("/proc/meminfo").splitlines():
        k, v = line.split(":", 1)
        info[k] = int(v.split()[0]) * 1024
    return {
        "total": info["MemTotal"],
        "available": info["MemAvailable"],
        "swap_total": info.get("SwapTotal", 0),
        "swap_free": info.get("SwapFree", 0),
    }


def temps():
    out = []
    base = "/sys/class/thermal"
    for z in sorted(os.listdir(base)):
        if not z.startswith("thermal_zone"):
            continue
        try:
            t = int(read(f"{base}/{z}/temp")) / 1000
            kind = read(f"{base}/{z}/type")
        except OSError:
            continue
        out.append({"name": kind, "c": round(t, 1)})
    hw = "/sys/class/hwmon"
    for h in sorted(os.listdir(hw)) if os.path.isdir(hw) else []:
        try:
            name = read(f"{hw}/{h}/name")
        except OSError:
            continue
        if name not in ("coretemp", "k10temp", "nvme", "acpitz"):
            continue
        try:
            t = int(read(f"{hw}/{h}/temp1_input")) / 1000
        except OSError:
            continue
        out.append({"name": name, "c": round(t, 1)})
    return out


def power():
    base = "/sys/class/power_supply"
    res = {"ac": None, "batteries": []}
    for s in sorted(os.listdir(base)):
        p = f"{base}/{s}"
        try:
            kind = read(f"{p}/type")
        except OSError:
            continue
        if kind == "Mains":
            res["ac"] = read(f"{p}/online") == "1"
        elif kind == "Battery":
            b = {"name": s}
            for k in ("capacity", "status"):
                try:
                    b[k] = read(f"{p}/{k}")
                except OSError:
                    pass
            if "capacity" in b:
                b["capacity"] = int(b["capacity"])
            res["batteries"].append(b)
    return res


def disks():
    out = []
    seen = set()
    for line in read("/proc/self/mounts").splitlines():
        dev, mnt, fstype = line.split()[:3]
        if fstype not in ("ext4", "xfs", "btrfs", "zfs", "f2fs", "vfat"):
            continue
        if mnt != "/" and not mnt.startswith(("/srv", "/data", "/mnt", "/var", "/home", "/boot")):
            continue
        if dev in seen and fstype != "btrfs":
            continue
        seen.add(dev)
        try:
            u = shutil.disk_usage(mnt)
        except OSError:
            continue
        out.append({"mount": mnt, "total": u.total, "used": u.used})
    return out[:6]


def failed_units():
    data = json.loads(run(["systemctl", "list-units", "--state=failed", "--no-legend", "-o", "json"]))
    return [u.get("unit") for u in data]


def unit_states():
    props = "Id,ActiveState,SubState,Result,LoadState"
    out = {}
    for u in UNITS:
        txt = run(["systemctl", "show", "-p", props, u])
        d = dict(line.split("=", 1) for line in txt.splitlines() if "=" in line)
        out[u.rsplit(".", 1)[0]] = {
            "active": d.get("ActiveState"),
            "sub": d.get("SubState"),
            "result": d.get("Result"),
            "loaded": d.get("LoadState") == "loaded",
        }
    return out


def backups():
    out = {}
    for name, (timer, service) in BACKUP_TIMERS.items():
        t = dict(
            line.split("=", 1)
            for line in run(
                ["systemctl", "show", "--timestamp=unix", "-p", "LoadState,LastTriggerUSec,NextElapseUSecRealtime", timer]
            ).splitlines()
            if "=" in line
        )
        s = dict(
            line.split("=", 1)
            for line in run(
                ["systemctl", "show", "--timestamp=unix", "-p", "Result,ActiveState,ExecMainExitTimestamp,ExecMainStatus", service]
            ).splitlines()
            if "=" in line
        )
        if t.get("LoadState") != "loaded":
            out[name] = {"enabled": False}
            continue

        def ts(v):
            v = (v or "").lstrip("@")
            return int(v) if v.isdigit() and int(v) > 0 else None

        out[name] = {
            "enabled": True,
            "last_trigger": ts(t.get("LastTriggerUSec")),
            "last_exit": ts(s.get("ExecMainExitTimestamp")),
            "result": s.get("Result"),
            "exit_status": s.get("ExecMainStatus"),
            "active": s.get("ActiveState"),
        }
    return out


def deploy():
    s = dict(
        line.split("=", 1)
        for line in run(
            ["systemctl", "show", "--timestamp=unix", "-p", "Result,ActiveState,ExecMainExitTimestamp,ExecMainStatus", "lab-update-apply.service"]
        ).splitlines()
        if "=" in line
    )
    res = {
        "result": s.get("Result"),
        "exit_status": s.get("ExecMainStatus"),
        "active": s.get("ActiveState"),
        "last_exit": (lambda v: int(v) if v.isdigit() and int(v) > 0 else None)((s.get("ExecMainExitTimestamp") or "").lstrip("@")),
    }
    # lab-update logs "bandit-lab activated and recorded at <rev>" only after the
    # signature gate passed, so a rev found there was signed by a trusted key.
    try:
        txt = run(
            ["journalctl", "-u", "lab-update-apply.service", "-o", "cat", "-n", "2000", "--no-pager", "--grep", "activated and recorded at"],
            timeout=TIMEOUT,
        )
        m = re.findall(r"recorded at ([0-9a-f]{40})", txt)
        res["deployed_rev"] = m[-1] if m else None
        res["signed"] = bool(m)
    except Exception:  # noqa: BLE001 - journal grep returns 1 on no match
        res["deployed_rev"] = None
        res["signed"] = False
    # Mirror checkout HEAD (what lab-update merged last), for comparison.
    try:
        res["checkout_rev"] = run(["git", "-c", f"safe.directory={REPO}", "-C", REPO, "rev-parse", "HEAD"]).strip()
    except Exception as e:  # noqa: BLE001
        res["checkout_rev"] = None
        res["checkout_error"] = str(e)[:120]
    if res["deployed_rev"] and res.get("checkout_rev"):
        res["signed"] = res["deployed_rev"] == res["checkout_rev"]
    return res


def containers():
    out = []
    for line in run(["docker", "ps", "-a", "--format", "{{json .}}"]).splitlines():
        if not line.strip():
            continue
        c = json.loads(line)
        status = c.get("Status", "")
        health = None
        m = re.search(r"\((healthy|unhealthy|health: starting)\)", status)
        if m:
            health = m.group(1).replace("health: ", "")
        out.append({"name": c.get("Names"), "state": c.get("State"), "health": health, "status": status[:40]})
    return sorted(out, key=lambda c: c["name"] or "")


def tailscale():
    d = json.loads(run(["tailscale", "status", "--json"]))
    peers = (d.get("Peer") or {}).values()
    own = d.get("Self") or {}
    ips = own.get("TailscaleIPs") or []
    return {
        "backend": d.get("BackendState"),
        "ip": next((i for i in ips if ":" not in i), ips[0] if ips else None),
        "peers": len(peers),
        "online": sum(1 for p in peers if p.get("Online")),
    }


def crowdsec():
    txt = run(["cscli", "decisions", "list", "-o", "json"]).strip()
    data = json.loads(txt) if txt and txt != "null" else []
    n = sum(len(a.get("decisions") or []) for a in data)
    return {"decisions": n}


def main():
    snap = {
        "generated": int(time.time()),
        "host": probe(host),
        "memory": probe(memory),
        "temps": probe(temps),
        "power": probe(power),
        "disks": probe(disks),
        "failed": probe(failed_units),
        "units": probe(unit_states),
        "backups": probe(backups),
        "deploy": probe(deploy),
        "containers": probe(containers),
        "tailscale": probe(tailscale),
        "crowdsec": probe(crowdsec),
    }
    os.makedirs(OUT_DIR, mode=0o755, exist_ok=True)
    tmp = OUT + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    with os.fdopen(fd, "w") as f:
        json.dump(snap, f, separators=(",", ":"))
    os.chmod(tmp, 0o644)
    os.replace(tmp, OUT)


if __name__ == "__main__":
    main()
