"""lab-console: read-only status dashboard for bandit-lab's tty1.

Reads only /run/lab-console/status.json (written by lab-console-collect) and
the palette roles JSON baked in at build time. It runs no commands and offers
no action that changes the system; quitting just lets systemd restart it.
"""

import json
import os
import time

from rich.text import Text
from textual.app import App, ComposeResult
from textual.containers import Grid
from textual.theme import Theme
from textual.widgets import Static

STATUS = os.environ.get("LAB_CONSOLE_STATUS", "/run/lab-console/status.json")
ROLES_FILE = os.environ["LAB_CONSOLE_ROLES"]
STALE_S = 90
BACKUP_WARN_S = 26 * 3600  # alerting.nix: backup alert thresholds
BACKUP_CRIT_S = 36 * 3600

with open(ROLES_FILE) as f:
    C = json.load(f)


def age(sec):
    if sec is None:
        return "never"
    sec = int(sec)
    if sec < 120:
        return f"{sec}s"
    if sec < 7200:
        return f"{sec // 60}m"
    if sec < 172800:
        return f"{sec // 3600}h{(sec % 3600) // 60:02d}"
    return f"{sec // 86400}d"


def size(n):
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024:
            return f"{n:.0f}{unit}"
        n /= 1024
    return f"{n:.0f}P"


def bar(frac, width=12):
    frac = max(0.0, min(1.0, frac))
    fill = round(frac * width)
    colour = C["crit"] if frac >= 0.9 else C["warn"] if frac >= 0.75 else C["ok"]
    t = Text()
    t.append("█" * fill, style=colour)
    t.append("░" * (width - fill), style=C["line"])
    t.append(f" {frac * 100:3.0f}%", style=C["fg"])
    return t


def dot(state):
    colour = {"ok": C["ok"], "warn": C["warn"], "crit": C["crit"], "info": C["info"]}.get(state, C["muted"])
    return Text("■ ", style=colour)


def err(t, d):
    t.append(f"  ! {d.get('error', 'error')}\n", style=C["warn"])


def is_err(d):
    return isinstance(d, dict) and "error" in d


class Panel(Static):
    def __init__(self, title, **kw):
        super().__init__(**kw)
        self.border_title = title


class Console(App):
    ENABLE_COMMAND_PALETTE = False
    TITLE = "bandit-lab"
    BINDINGS = []  # nothing to do here; ctrl+q exits and systemd restarts us

    CSS = """
    Screen { background: $background; color: $foreground; layout: vertical; }
    #header { height: 1; background: $surface; color: $foreground; padding: 0 1; }
    #stale { height: 1; background: $warning; color: $background; display: none; padding: 0 1; }
    #stale.on { display: block; }
    #grid { grid-size: 3 2; grid-gutter: 0 0; height: 1fr; }
    #grid.narrow { grid-size: 2 3; }
    Panel {
        border: solid $panel-lighten-1;
        border-title-color: $accent;
        border-title-style: bold;
        background: $background;
        padding: 0 1;
        height: 100%;
        overflow: hidden hidden;
    }
    """

    def compose(self) -> ComposeResult:
        yield Static(id="header")
        yield Static(id="stale")
        with Grid(id="grid"):
            yield Panel("SERVICES", id="services")
            yield Panel("CONTAINERS", id="containers")
            yield Panel("BACKUPS", id="backups")
            yield Panel("RESOURCES", id="resources")
            yield Panel("POWER / TEMP", id="power")
            yield Panel("NETWORK", id="network")

    def on_mount(self) -> None:
        self.register_theme(
            Theme(
                name="bandit",
                dark=True,
                primary=C["info"],
                secondary=C["dim"],
                accent=C["accent"],
                warning=C["warn"],
                error=C["crit"],
                success=C["ok"],
                foreground=C["fg"],
                background=C["bg"],
                surface=C["surface"],
                panel=C["borderInactive"],
            )
        )
        self.theme = "bandit"
        self.refresh_data()
        self.set_interval(5, self.refresh_data)
        self.set_interval(1, self.tick)

    def on_resize(self, event) -> None:
        self.query_one("#grid").set_class(event.size.width < 100, "narrow")

    def load(self):
        try:
            with open(STATUS) as f:
                return json.load(f)
        except (OSError, ValueError) as e:
            return {"error": str(e)[:120]}

    def tick(self) -> None:
        self.render_header()

    def render_header(self) -> None:
        d = getattr(self, "data", {}) or {}
        h = d.get("host") or {}
        dep = d.get("deploy") or {}
        t = Text()
        t.append(h.get("hostname", "bandit-lab") if not is_err(h) else "bandit-lab", style=f"bold {C['bright']}")
        if not is_err(h) and "uptime_s" in h:
            t.append(f"  up {age(h['uptime_s'])}", style=C["dim"])
        t.append("  " + time.strftime("%Y-%m-%d %H:%M:%S"), style=C["fg"])
        if not is_err(dep):
            rev = dep.get("deployed_rev") or dep.get("checkout_rev")
            t.append("  rev ", style=C["muted"])
            t.append((rev or "unknown")[:10], style=C["info"])
            if dep.get("signed"):
                t.append(" [SIGNED]", style=C["ok"])
            else:
                t.append(" [UNVERIFIED]", style=C["warn"])
        self.query_one("#header", Static).update(t)

    def refresh_data(self) -> None:
        d = self.load()
        self.data = d
        now = time.time()
        stale = self.query_one("#stale", Static)
        gen = d.get("generated")
        if "error" in d and gen is None:
            stale.update(f"NO STATUS DATA: {d['error']}")
            stale.add_class("on")
        elif gen is None or now - gen > STALE_S:
            stale.update(f"STALE DATA: last snapshot {age(now - gen) if gen else 'never'} ago (lab-console-collect)")
            stale.add_class("on")
        else:
            stale.remove_class("on")
        self.render_header()
        self.query_one("#services", Panel).update(self.services(d))
        self.query_one("#containers", Panel).update(self.containers(d))
        self.query_one("#backups", Panel).update(self.backups(d, now))
        self.query_one("#resources", Panel).update(self.resources(d))
        self.query_one("#power", Panel).update(self.power(d))
        self.query_one("#network", Panel).update(self.network(d))

    # ── panels ──────────────────────────────────────────────────────────
    def services(self, d):
        t = Text()
        units = d.get("units") or {}
        if is_err(units):
            err(t, units)
            units = {}
        for name, u in units.items():
            short = name.replace("cloudflared-tunnel-bandit-lab", "cloudflared").replace("docker-", "ctr:")
            if not u.get("loaded"):
                state = "none"
            elif u.get("active") == "active":
                state = "ok"
            elif u.get("active") == "failed" or u.get("result") not in (None, "success"):
                state = "crit"
            elif name == "lab-update-apply" and u.get("active") == "inactive":
                state = "ok"
            elif u.get("active") in ("activating", "reloading", "deactivating"):
                state = "info"
            else:
                state = "warn"
            t.append_text(dot(state))
            t.append(f"{short}\n", style=C["fg"])
        failed = d.get("failed")
        if is_err(failed):
            err(t, failed)
        elif failed:
            t.append(f"\n{len(failed)} failed:\n", style=f"bold {C['crit']}")
            for u in failed[:4]:
                t.append(f"  {u}\n", style=C["crit"])
        else:
            t.append("\nno failed units\n", style=C["ok"])
        return t

    def containers(self, d):
        t = Text()
        cs = d.get("containers")
        if is_err(cs):
            err(t, cs)
            return t
        for c in cs or []:
            if c.get("state") != "running":
                state = "crit" if c.get("state") in ("exited", "dead") else "warn"
            elif c.get("health") == "unhealthy":
                state = "crit"
            elif c.get("health") == "starting":
                state = "info"
            else:
                state = "ok"
            t.append_text(dot(state))
            t.append(f"{c.get('name')}", style=C["fg"])
            if c.get("health"):
                t.append(f" {c['health']}", style=C["muted"])
            t.append("\n")
        if not cs:
            t.append("no containers\n", style=C["muted"])
        return t

    def backups(self, d, now):
        t = Text()
        b = d.get("backups")
        if is_err(b):
            err(t, b)
        else:
            for name, j in (b or {}).items():
                if not j.get("enabled"):
                    t.append_text(dot("none"))
                    t.append(f"{name}: not enabled\n", style=C["muted"])
                    continue
                last = j.get("last_exit") or j.get("last_trigger")
                a = now - last if last else None
                if j.get("active") == "activating":
                    state = "info"
                elif j.get("result") not in (None, "success") or a is None or a > BACKUP_CRIT_S:
                    state = "crit"
                elif a > BACKUP_WARN_S:
                    state = "warn"
                else:
                    state = "ok"
                t.append_text(dot(state))
                t.append(f"{name}", style=C["fg"])
                t.append(f"  {age(a)} ago  {j.get('result') or '-'}\n", style=C["dim"])
        dep = d.get("deploy") or {}
        t.append("\nlab-update-apply\n", style=C["muted"])
        if is_err(dep):
            err(t, dep)
        else:
            ok = dep.get("result") == "success"
            t.append_text(dot("ok" if ok else "crit"))
            last = dep.get("last_exit")
            t.append(f"{dep.get('result') or '-'}  {age(now - last) if last else 'never'} ago\n", style=C["fg"])
        return t

    def resources(self, d):
        t = Text()
        h = d.get("host") or {}
        if is_err(h):
            err(t, h)
        else:
            cpus = h.get("cpus") or 1
            l1, l5, l15 = h.get("load", [0, 0, 0])
            t.append("load ", style=C["muted"])
            t.append_text(bar(l1 / cpus, 10))
            t.append(f"\n     {l1:.2f} {l5:.2f} {l15:.2f} /{cpus}\n", style=C["dim"])
        m = d.get("memory") or {}
        if is_err(m):
            err(t, m)
        elif m.get("total"):
            used = m["total"] - m["available"]
            t.append("mem  ", style=C["muted"])
            t.append_text(bar(used / m["total"], 10))
            t.append(f"\n     {size(used)}/{size(m['total'])}\n", style=C["dim"])
        ds = d.get("disks")
        if is_err(ds):
            err(t, ds)
        else:
            for dk in ds or []:
                label = dk["mount"][-4:].ljust(4)
                t.append(f"{label} ", style=C["muted"])
                t.append_text(bar(dk["used"] / dk["total"] if dk["total"] else 0, 10))
                t.append("\n")
        return t

    def power(self, d):
        t = Text()
        p = d.get("power") or {}
        if is_err(p):
            err(t, p)
        else:
            ac = p.get("ac")
            t.append_text(dot("ok" if ac else "warn" if ac is False else "none"))
            t.append("AC " + ("online" if ac else "OFFLINE" if ac is False else "n/a") + "\n", style=C["fg"])
            for b in p.get("batteries") or []:
                cap = b.get("capacity")
                state = "ok" if cap is None or cap > 50 else "warn" if cap > 20 else "crit"
                t.append_text(dot(state))
                t.append(f"{b['name']} {cap if cap is not None else '?'}% {b.get('status', '')}\n", style=C["fg"])
        ts = d.get("temps")
        if is_err(ts):
            err(t, ts)
        else:
            shown = 0
            for s in ts or []:
                if shown >= 6:
                    break
                c = s["c"]
                state = "crit" if c >= 90 else "warn" if c >= 75 else "ok"
                t.append_text(dot(state))
                t.append(f"{s['name'][:12]:<12} {c:5.1f}°C\n", style=C["fg"])
                shown += 1
        return t

    def network(self, d):
        t = Text()
        ts = d.get("tailscale") or {}
        if is_err(ts):
            err(t, ts)
        else:
            running = ts.get("backend") == "Running"
            t.append_text(dot("ok" if running else "crit"))
            t.append(f"tailscale {ts.get('backend')}\n", style=C["fg"])
            t.append(f"  {ts.get('ip') or '-'}\n", style=C["info"])
            t.append(f"  peers {ts.get('online', 0)}/{ts.get('peers', 0)} online\n", style=C["dim"])
        cs = d.get("crowdsec") or {}
        if is_err(cs):
            err(t, cs)
        else:
            n = cs.get("decisions", 0)
            t.append_text(dot("info"))
            t.append(f"crowdsec bans {n}\n", style=C["fg"])
        return t


if __name__ == "__main__":
    Console().run()
