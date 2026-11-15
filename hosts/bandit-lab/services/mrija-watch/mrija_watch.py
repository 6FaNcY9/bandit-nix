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
import sys
import tempfile
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


# --- CLI -------------------------------------------------------------------


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="mrija-watch")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("collect")
    sub.add_parser("digest")
    args = parser.parse_args(argv)

    state_dir = Path(os.environ.get("STATE_DIR", "/var/lib/mrija-watch"))
    state_path = state_dir / "state.json"
    state = load_state(state_path)

    if args.cmd == "collect":
        save_state(state_path, state)
    elif args.cmd == "digest":
        save_state(state_path, state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
