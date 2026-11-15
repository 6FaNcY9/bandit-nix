"""mrija-watch: daily protection watch for mrija.org.

Privacy rule (hard): notification text, the digest, journal lines and the
state file may contain only a mailbox name, a number, a 2-letter country
code, a rule name or a web path. Never a mail subject, body, attachment
filename or any third-party address.
"""

import argparse
import json
import os
import re
import ssl
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from dataclasses import dataclass, field
from email.parser import BytesParser
from pathlib import Path

# Attachment extensions that are risky regardless of content.
RISKY_EXT = {"iso", "img", "vhd", "js", "vbs", "hta", "lnk", "scr", "exe"}
# "with esmtpsa" = authenticated submission; "esmtps" alone is not.
_AUTH_RE = re.compile(r"with esmtps?a\b")
_IP_RE = re.compile(r"\[([0-9a-fA-F:.]+)\]")
# Password-test probe subject; only the boolean result is used, never stored.
_PWTEST_RE = re.compile(r"mrija\.org:(?:25|465|587)\s+\S+@mrija\.org")


# --- state -----------------------------------------------------------------


def load_state(path: Path) -> dict:
    """Load the JSON state file, or {} when it does not exist."""
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        return {}


def save_state(path: Path, state: dict) -> None:
    """Write state atomically (temp file + os.replace)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".state-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(state, fh)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


# --- mail scan -------------------------------------------------------------


class GeoIP:
    """Thin maxminddb wrapper. country_of(ip) -> 2-letter code or None."""

    def __init__(self, path=None):
        self._reader = None
        if path and os.path.exists(path):
            import maxminddb

            self._reader = maxminddb.open_database(path)

    def country_of(self, ip):
        if not self._reader:
            return None
        try:
            rec = self._reader.get(ip)
        except (ValueError, TypeError):
            return None
        if not rec:
            return None
        return (rec.get("country") or {}).get("iso_code")


@dataclass
class MailFindings:
    ndr_per_mailbox: dict = field(default_factory=dict)
    auth_ndr_foreign: list = field(default_factory=list)  # (mailbox, country)
    password_test_hits: int = 0
    risky_attach_total: int = 0
    risky_attach_seen: int = 0
    spoof_spf_fail: int = 0
    new_cursor: dict = field(default_factory=dict)


def _is_seen(filename: str) -> bool:
    """Maildir Seen flag: the 'S' flag in the ':2,<flags>' info part."""
    _, _, info = filename.partition(":2,")
    return "S" in info


def _is_ndr(msg) -> bool:
    ctype = (msg.get_content_type() or "").lower()
    if ctype == "multipart/report" and "delivery-status" in (
        msg.get_param("report-type") or ""
    ):
        return True
    return "MAILER-DAEMON" in (msg.get("From") or "").upper()


def _foreign_auth_country(msg, geoip):
    """Country of the authenticated-send IP in the included original, or None.

    Only fires for an authenticated submission (esmtpsa) from outside AT.
    """
    for part in msg.walk():
        ctype = (part.get_content_type() or "").lower()
        if ctype not in ("message/rfc822", "text/rfc822-headers"):
            continue
        payload = part.get_payload()
        embedded = payload[0] if isinstance(payload, list) and payload else part
        received = embedded.get_all("Received", []) if hasattr(
            embedded, "get_all"
        ) else []
        for line in received:
            line = " ".join(line.split())
            if not _AUTH_RE.search(line):
                continue
            m = _IP_RE.search(line)
            if not m:
                continue
            country = geoip.country_of(m.group(1))
            if country and country != "AT":
                return country
    return None


def _spf_failed(msg) -> bool:
    for hdr in msg.get_all("Authentication-Results", []):
        if re.search(r"spf=fail\b", hdr, re.I):
            return True
    for hdr in msg.get_all("Received-SPF", []):
        if re.match(r"\s*fail\b", hdr, re.I):
            return True
    return False


def _count_risky_attachments(msg) -> int:
    count = 0
    for part in msg.walk():
        name = part.get_filename()
        if not name:
            continue
        ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
        if ext in RISKY_EXT:
            count += 1
    return count


def scan_mail(maildir: Path, cursor: dict, geoip) -> MailFindings:
    """Scan each mailbox's cur/ and new/ for files newer than cursor[mailbox].

    Reads mail content but stores only privacy-safe counts and codes.
    """
    maildir = Path(maildir)
    out = MailFindings(new_cursor=dict(cursor))
    parser = BytesParser()
    if not maildir.is_dir():
        return out
    for box_dir in sorted(p for p in maildir.iterdir() if p.is_dir()):
        mailbox = box_dir.name
        last = cursor.get(mailbox, "")
        high = last
        for sub in ("cur", "new"):
            d = box_dir / sub
            if not d.is_dir():
                continue
            for f in sorted(d.iterdir()):
                if not f.is_file() or f.name <= last:
                    continue
                if f.name > high:
                    high = f.name
                try:
                    with open(f, "rb") as fh:
                        msg = parser.parse(fh)
                except OSError:
                    continue
                seen = _is_seen(f.name)
                if _is_ndr(msg):
                    out.ndr_per_mailbox[mailbox] = (
                        out.ndr_per_mailbox.get(mailbox, 0) + 1
                    )
                    country = _foreign_auth_country(msg, geoip)
                    if country:
                        out.auth_ndr_foreign.append((mailbox, country))
                else:
                    if _PWTEST_RE.search(msg.get("Subject") or ""):
                        out.password_test_hits += 1
                    frm = (msg.get("From") or "").lower()
                    if "@mrija.org" in frm and _spf_failed(msg):
                        out.spoof_spf_fail += 1
                risky = _count_risky_attachments(msg)
                out.risky_attach_total += risky
                if seen:
                    out.risky_attach_seen += risky
        if high:
            out.new_cursor[mailbox] = high
    return out


# --- web manifest diff -----------------------------------------------------

_PHP_EXT = {"php", "php3", "php4", "php5", "php7", "phtml", "phar"}
_SENSITIVE = {".htaccess", ".user.ini", "wp-config.php"}


@dataclass
class WebFindings:
    added: list = field(default_factory=list)
    removed: list = field(default_factory=list)
    changed: list = field(default_factory=list)
    instant: list = field(default_factory=list)  # "rule: path"
    digest_groups: dict = field(default_factory=dict)  # group -> changed count


def parse_manifest(text: str) -> dict:
    """Parse `rsync --list-only` lines into {path: (perms, size, mtime)}."""
    out = {}
    for line in text.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5:
            continue
        perms, size, date, clock, path = parts
        try:
            size = int(size.replace(",", ""))
        except ValueError:
            continue
        out[path] = (perms, size, f"{date} {clock}")
    return out


def _digest_group(path: str) -> str:
    segs = path.split("/")
    if segs[0] == "wp-content" and len(segs) >= 3:
        return "/".join(segs[:3])
    return segs[0]


def _instant_rules(path, perms, is_added, is_changed, version_changed):
    """Rule names that fire for one added/changed path (privacy-safe)."""
    segs = path.split("/")
    base = segs[-1]
    ext = base.rsplit(".", 1)[-1].lower() if "." in base else ""
    hit = []
    if "mu-plugins" in segs:
        hit.append("mu-plugins")
    if "uploads" in segs and ext in _PHP_EXT:
        hit.append("uploads-php")
    if base in _SENSITIVE:
        hit.append("sensitive-file")
    if (
        base == "wp-inmri.php"
        or base.startswith(".htaccess.bak")
        or any(s.endswith("vgh") for s in segs)
    ):
        hit.append("ioc")
    if is_added and perms.startswith("d") and len(segs) == 1:
        hit.append("new-topdir")
    if base.endswith("authorized_keys"):
        hit.append("authorized-keys")
    if (
        is_changed
        and ext in _PHP_EXT
        and (len(segs) == 1 or segs[0] in ("wp-includes", "wp-admin"))
        and not version_changed
    ):
        hit.append("core-file")
    return hit


def diff_web(old: dict, new: dict) -> WebFindings:
    """Diff two manifests. An empty `old` is the first-run baseline."""
    out = WebFindings()
    if not old:
        return out
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed = sorted(
        p
        for p in set(old) & set(new)
        if old[p][1] != new[p][1] or old[p][2] != new[p][2]
    )
    out.added, out.removed, out.changed = added, removed, changed
    version_changed = any(p.endswith("wp-includes/version.php") for p in changed)
    for p in changed:
        out.digest_groups[_digest_group(p)] = (
            out.digest_groups.get(_digest_group(p), 0) + 1
        )
    for p in added + changed:
        perms = new[p][0]
        rules = _instant_rules(
            p, perms, p in set(added), p in set(changed), version_changed
        )
        for rule in rules:
            out.instant.append(f"{rule}: {p}")
    return out


# --- dns diff --------------------------------------------------------------


@dataclass
class DnsFindings:
    changed: list = field(default_factory=list)  # record names
    instant: list = field(default_factory=list)  # only NS or MX


def diff_dns(old: dict, new: dict) -> DnsFindings:
    """Diff two DNS snapshots (type -> sorted values). Empty old = baseline."""
    out = DnsFindings()
    if not old:
        return out
    for rtype in sorted(set(old) | set(new)):
        if old.get(rtype) != new.get(rtype):
            out.changed.append(rtype)
            if rtype in ("NS", "MX"):
                out.instant.append(rtype)
    return out


# --- report builder + redaction guard --------------------------------------

# One mailbox crossing this many NDRs in 24h pushes instantly.
NDR_INSTANT = 20
# This many authenticated NDRs from outside AT push instantly.
FOREIGN_NDR_INSTANT = 3


@dataclass
class Report:
    instant: list = field(default_factory=list)  # (title, body), both "Mrija: "
    digest: str = ""


def assert_clean(text: str, forbidden: list) -> None:
    """Raise if any forbidden token (a real subject/address) is in `text`."""
    for tok in forbidden:
        if tok and tok in text:
            raise ValueError("mrija-watch: forbidden token leaked into output")


def build_report(mail, web, dns, meta) -> Report:
    rep = Report()

    if mail.password_test_hits:
        rep.instant.append((
            "Mrija: Passwort-Test erkannt",
            f"Mrija: Betreff mit Mailbox-Passwort gesehen ({mail.password_test_hits})",
        ))
    for box, n in sorted(mail.ndr_per_mailbox.items()):
        if n >= NDR_INSTANT:
            rep.instant.append((
                "Mrija: Viele Unzustellbar-Mails",
                f"Mrija: {box} {n} Bounces in 24 h",
            ))
    if len(mail.auth_ndr_foreign) >= FOREIGN_NDR_INSTANT:
        countries = sorted({c for _, c in mail.auth_ndr_foreign})
        rep.instant.append((
            "Mrija: Versand aus dem Ausland",
            f"Mrija: {len(mail.auth_ndr_foreign)} Bounces, Länder {', '.join(countries)}",
        ))
    for item in web.instant:
        rep.instant.append((
            "Mrija: Web-Datei verdächtig",
            f"Mrija: {item}",
        ))
    for rtype in dns.instant:
        rep.instant.append((
            f"Mrija: DNS {rtype} geändert",
            f"Mrija: {rtype} Eintrag geändert",
        ))

    total_ndr = sum(mail.ndr_per_mailbox.values())
    sync_age = meta.get("sync_age_hours", 0.0)
    cert_days = meta.get("cert_days", 0)
    http_ok = meta.get("http_ok", False)
    errors = meta.get("errors", [])
    quiet = (
        total_ndr == 0
        and mail.risky_attach_total == 0
        and mail.spoof_spf_fail == 0
        and not mail.auth_ndr_foreign
        and not web.instant
        and not web.digest_groups
        and not dns.changed
        and not errors
    )

    lines = []
    if quiet:
        lines.append("Mrija: alles ruhig, keine Auffälligkeiten")
    else:
        lines.append(
            f"Mrija: {total_ndr} Bounces, {mail.risky_attach_total} riskante Anhänge,"
            f" {mail.spoof_spf_fail} SPF-Fehler"
        )
        if web.digest_groups:
            tops = ", ".join(
                f"{g.split('/')[-1]} {n}"
                for g, n in sorted(web.digest_groups.items())[:3]
            )
            lines.append(f"Mrija: Datei-Änderungen: {tops}")
        if "TXT" in dns.changed:
            lines.append("Mrija: DNS TXT-Eintrag geändert, bitte prüfen")
        if errors:
            lines.append(f"Mrija: Fehler: {'; '.join(errors)}")
    lines.append(f"Mrija: letzter Mail-Sync vor {sync_age:.0f} h")
    lines.append(
        f"Mrija: Web {'ok' if http_ok else 'nicht erreichbar'},"
        f" Zertifikat {cert_days} Tage"
    )

    rep.digest = "\n".join(lines[:6])

    # Self-check: a caller that has the raw subjects/addresses (never copied
    # into the findings) can pass them as meta["forbidden"] to prove the
    # emitted text is clean. Default empty -> no-op.
    forbidden = meta.get("forbidden", [])
    assert_clean(rep.digest, forbidden)
    for title, body in rep.instant:
        assert_clean(title + " " + body, forbidden)
    return rep


# --- collectors ------------------------------------------------------------


class CollectorError(Exception):
    """A shell collector (rsync/dig) failed; state must stay unchanged."""


def run_rsync_manifest(remote: str, keypath: str) -> str:
    """`rsync --list-only` of the remote tree; returns the manifest text."""
    rsync = os.environ.get("RSYNC", "rsync")
    ssh = f"ssh -i {keypath} -o BatchMode=yes"
    known = os.environ.get("MRIJA_KNOWN_HOSTS")
    if known:
        ssh += f" -o UserKnownHostsFile={known} -o StrictHostKeyChecking=yes"
    cmd = [rsync, "--list-only", "-r", "-e", ssh, remote]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except (subprocess.TimeoutExpired, OSError) as e:
        raise CollectorError(f"rsync failed: {e.__class__.__name__}") from e
    if r.returncode != 0:
        raise CollectorError(f"rsync exit {r.returncode}")
    return r.stdout


def run_dig(name: str) -> dict:
    """Query DNS for NS/MX/TXT and DMARC. Returns {type: sorted values}."""
    dig = os.environ.get("DIG", "dig")
    queries = {
        "NS": (name, "NS"),
        "MX": (name, "MX"),
        "TXT": (name, "TXT"),
        "DMARC": (f"_dmarc.{name}", "TXT"),
    }
    out = {}
    for key, (qname, qtype) in queries.items():
        try:
            r = subprocess.run(
                [dig, "+short", "@1.1.1.1", qname, qtype],
                capture_output=True,
                text=True,
                timeout=20,
            )
        except (subprocess.TimeoutExpired, OSError) as e:
            raise CollectorError(f"dig failed: {e.__class__.__name__}") from e
        if r.returncode != 0:
            raise CollectorError(f"dig exit {r.returncode}")
        out[key] = sorted(ln for ln in r.stdout.splitlines() if ln.strip())
    return out


def post_ntfy(url, topic, token, title, body, priority="default") -> bool:
    """POST one ntfy message. The body is an argument, never real content."""
    curl = os.environ.get("CURL", "curl")
    cmd = [
        curl,
        "-fsS",
        "-H",
        f"Authorization: Bearer {token}",
        "-H",
        f"Title: {title}",
        "-H",
        f"Priority: {priority}",
        "--data-raw",
        body,
        f"{url}/{topic}",
    ]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (subprocess.TimeoutExpired, OSError):
        return False
    return r.returncode == 0


def check_http(url: str):
    """Return (reachable, days_until_cert_expiry). Never raises."""
    import urllib.request

    host = re.sub(r"^https?://", "", url).split("/")[0]
    ok = False
    cert_days = 0
    try:
        ctx = ssl.create_default_context()
        with socket_connect(host, ctx) as ssock:
            cert = ssock.getpeercert()
        expire = datetime.strptime(
            cert["notAfter"], "%b %d %H:%M:%S %Y %Z"
        ).replace(tzinfo=timezone.utc)
        cert_days = (expire - datetime.now(timezone.utc)).days
    except Exception:
        cert_days = 0
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            ok = 200 <= resp.status < 400
    except Exception:
        ok = False
    return ok, cert_days


def socket_connect(host, ctx):
    import socket

    sock = socket.create_connection((host, 443), timeout=15)
    return ctx.wrap_socket(sock, server_hostname=host)


# --- run loop --------------------------------------------------------------


def _maildir_newest_mtime(maildir: Path) -> float:
    newest = 0.0
    maildir = Path(maildir)
    if maildir.is_dir():
        for root, _dirs, files in os.walk(maildir):
            for f in files:
                try:
                    newest = max(newest, os.path.getmtime(os.path.join(root, f)))
                except OSError:
                    pass
    return newest


def run_collect(cfg) -> dict:
    """Collect mail/web/dns, push instants, persist state and the digest."""
    state = load_state(cfg["state_path"])
    errors = []

    mail = scan_mail(cfg["maildir"], state.get("maildir_cursor", {}), cfg["geoip"])

    old_web = state.get("web_manifest", "")
    new_web = None
    try:
        new_web = run_rsync_manifest(cfg["remote"], cfg["keypath"])
    except CollectorError as e:
        errors.append(str(e))
    web = diff_web(
        parse_manifest(old_web),
        parse_manifest(new_web if new_web is not None else old_web),
    )

    old_dns = state.get("dns", {})
    new_dns = None
    if cfg.get("dns_name"):
        try:
            new_dns = run_dig(cfg["dns_name"])
        except CollectorError as e:
            errors.append(str(e))
    dns = diff_dns(old_dns, new_dns if new_dns is not None else old_dns)

    http_ok, cert_days = True, 0
    if cfg.get("http_url"):
        http_ok, cert_days = check_http(cfg["http_url"])
        if not http_ok:
            errors.append("web nicht erreichbar")

    newest = _maildir_newest_mtime(cfg["maildir"])
    sync_age = (time.time() - newest) / 3600.0 if newest else 0.0
    meta = {
        "sync_age_hours": sync_age,
        "errors": errors,
        "http_ok": http_ok,
        "cert_days": cert_days,
        "updates": {},
    }
    report = build_report(mail, web, dns, meta)

    push_failed = False
    for title, body in report.instant:
        if not post_ntfy(
            cfg["ntfy_url"],
            cfg["ntfy_topic"],
            cfg["ntfy_token"],
            title,
            body,
            priority="high",
        ):
            push_failed = True

    # If an instant push failed, leave the whole state unchanged so the finding
    # is re-detected and re-pushed on the next run (like jerry-box's cursor).
    if not push_failed:
        state["maildir_cursor"] = mail.new_cursor
        if new_web is not None:
            state["web_manifest"] = new_web
        if new_dns is not None:
            state["dns"] = new_dns
        state["last_sync_mtime"] = newest
        state["pending_digest"] = report.digest
        save_state(cfg["state_path"], state)

    meta["instant_count"] = len(report.instant)
    meta["push_failed"] = push_failed
    return meta


def run_digest(cfg) -> bool:
    """Post the digest computed at collect time (heartbeat, priority default)."""
    state = load_state(cfg["state_path"])
    digest = state.get("pending_digest") or "Mrija: kein Bericht vorhanden"
    return post_ntfy(
        cfg["ntfy_url"],
        cfg["ntfy_topic"],
        cfg["ntfy_token"],
        "Mrija: Tagesbericht",
        digest,
        priority="default",
    )


def _cfg_from_env() -> dict:
    env = os.environ
    cred = env.get("CREDENTIALS_DIRECTORY", "")
    keypath = env.get("MRIJA_KEY") or (
        os.path.join(cred, "thehost") if cred else ""
    )
    state_dir = Path(env.get("STATE_DIR", "/var/lib/mrija-watch"))
    return {
        "state_path": state_dir / "state.json",
        "maildir": Path(
            env.get("MRIJA_MAILDIR", "/srv/containers/mrija-archive/maildir")
        ),
        "geoip": GeoIP(env.get("MRIJA_GEOIP")),
        "remote": env.get(
            "MRIJA_REMOTE", "mrija_org@s16.thehost.com.ua:www/mrija.org/"
        ),
        "keypath": keypath,
        "dns_name": env.get("MRIJA_DNS_NAME"),
        "http_url": env.get("MRIJA_HTTP_URL"),
        "ntfy_url": env.get("NTFY_URL", "http://127.0.0.1:2586"),
        "ntfy_topic": env.get("NTFY_TOPIC", "mrija"),
        "ntfy_token": env.get("NTFY_TOKEN", ""),
    }


# --- CLI -------------------------------------------------------------------


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="mrija-watch")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("collect")
    sub.add_parser("digest")
    args = parser.parse_args(argv)

    cfg = _cfg_from_env()
    if args.cmd == "collect":
        run_collect(cfg)
    elif args.cmd == "digest":
        run_digest(cfg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
