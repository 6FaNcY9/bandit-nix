import json
from pathlib import Path

import pytest

import mrija_watch as mw

MAILDIR = Path(__file__).parent / "testdata" / "maildir"
PW_TOKEN = "Hunter2SecretPW"


class FakeGeoIP:
    """Injected geoip for tests: maps the fixture IPs to countries."""

    _map = {"91.92.241.54": "NL", "193.154.0.1": "AT"}

    def country_of(self, ip):
        return self._map.get(ip)


@pytest.fixture
def findings():
    return mw.scan_mail(MAILDIR, {}, FakeGeoIP())


# --- Task 1: state ---------------------------------------------------------


def test_state_roundtrip(tmp_path):
    state = {
        "maildir_cursor": {"postmaster": "1700000000.M1.host"},
        "web_manifest": ["index.php"],
        "dns": {"MX": ["10 mail.mrija.org."]},
        "last_sync_mtime": 123.0,
    }
    path = tmp_path / "state.json"
    mw.save_state(path, state)
    assert mw.load_state(path) == state


def test_load_state_missing_returns_empty(tmp_path):
    assert mw.load_state(tmp_path / "nope.json") == {}


# --- Task 2: mail scan -----------------------------------------------------


def test_ndr_counted_per_mailbox(findings):
    assert findings.ndr_per_mailbox["postmaster"] == 3


def test_auth_ndr_foreign(findings):
    assert ("postmaster", "NL") in findings.auth_ndr_foreign
    # esmtps (no auth) and the AT-IP esmtpsa are both excluded.
    assert all(c == "NL" for _, c in findings.auth_ndr_foreign)
    assert ("admin", "AT") not in findings.auth_ndr_foreign
    assert len(findings.auth_ndr_foreign) == 1


def test_password_test_subject_hit_not_stored(findings):
    assert findings.password_test_hits == 1
    assert PW_TOKEN not in json.dumps(findings.__dict__, default=str)


def test_risky_attachment_seen_flag(findings):
    assert findings.risky_attach_total == 2
    assert findings.risky_attach_seen == 1


def test_spoof_from_spf_fail(findings):
    assert findings.spoof_spf_fail == 1


def test_ndr_without_original_skipped(findings):
    # The no-original bounce is counted as an NDR but adds nothing to foreign.
    assert findings.ndr_per_mailbox["postmaster"] == 3
    assert len(findings.auth_ndr_foreign) == 1


def test_malformed_maildir_name(findings):
    # The ".plain" file has no ":2," info part; scanning must not crash.
    assert findings.ndr_per_mailbox  # scan completed


# --- Task 3: web manifest diff ---------------------------------------------


def test_parse_manifest_line():
    line = "-rw-r--r--          1,234 2026/01/02 03:04:05 wp-content/index.php"
    m = mw.parse_manifest(line)
    assert m["wp-content/index.php"] == ("-rw-r--r--", 1234, "2026/01/02 03:04:05")


def test_first_run_is_baseline():
    new = mw.parse_manifest("-rw-r--r-- 10 2026/01/01 00:00:00 index.php")
    web = mw.diff_web({}, new)
    assert web.instant == []
    assert web.added == []


def test_instant_rules():
    old = mw.parse_manifest(
        "\n".join([
            "-rw-r--r-- 10 2026/01/01 00:00:00 .htaccess",
            "-rw-r--r-- 10 2026/01/01 00:00:00 wp-content/plugins/elementor/foo.js",
        ])
    )
    new = mw.parse_manifest(
        "\n".join([
            "-rw-r--r-- 20 2026/02/01 00:00:00 .htaccess",
            "-rw-r--r-- 10 2026/01/01 00:00:00 wp-content/mu-plugins/x/index.php",
            "-rw-r--r-- 10 2026/01/01 00:00:00 uploads/evil.php",
            "drwxr-xr-x 4096 2026/02/01 00:00:00 33vgh",
            "-rw-r--r-- 10 2026/01/01 00:00:00 wp-inmri.php",
            "-rw-r--r-- 20 2026/02/01 00:00:00 wp-content/plugins/elementor/foo.js",
        ])
    )
    web = mw.diff_web(old, new)
    joined = " ".join(web.instant)
    assert "wp-content/mu-plugins/x/index.php" in joined
    assert "uploads/evil.php" in joined
    assert ".htaccess" in joined
    assert "33vgh" in joined
    assert "wp-inmri.php" in joined
    # A normal plugin asset change is digest-only, grouped by directory.
    assert "wp-content/plugins/elementor/foo.js" not in joined
    assert web.digest_groups.get("wp-content/plugins/elementor") == 1


def test_core_update_not_flagged():
    old = mw.parse_manifest(
        "\n".join([
            "-rw-r--r-- 10 2026/01/01 00:00:00 wp-includes/class-wp.php",
            "-rw-r--r-- 10 2026/01/01 00:00:00 wp-includes/version.php",
        ])
    )
    new = mw.parse_manifest(
        "\n".join([
            "-rw-r--r-- 20 2026/02/01 00:00:00 wp-includes/class-wp.php",
            "-rw-r--r-- 20 2026/02/01 00:00:00 wp-includes/version.php",
        ])
    )
    web = mw.diff_web(old, new)
    assert not any("class-wp.php" in i for i in web.instant)


# --- Task 4: dns diff ------------------------------------------------------


def test_mx_change_is_instant():
    old = {"MX": ["10 mail.mrija.org."], "NS": ["ns.ledl.net."]}
    new = {"MX": ["10 evil.example.net."], "NS": ["ns.ledl.net."]}
    dns = mw.diff_dns(old, new)
    assert "MX" in dns.changed
    assert "MX" in dns.instant


def test_txt_change_digest_only():
    old = {"TXT": ["v=spf1 include:_spf.mrija.org -all"]}
    new = {"TXT": ["v=spf1 include:evil.example.net ~all"]}
    dns = mw.diff_dns(old, new)
    assert "TXT" in dns.changed
    assert dns.instant == []


def test_first_run_baseline():
    dns = mw.diff_dns({}, {"MX": ["10 mail.mrija.org."]})
    assert dns.changed == []
    assert dns.instant == []


# --- Task 5: report builder + redaction guard ------------------------------


def _meta(**kw):
    m = {
        "sync_age_hours": 1.0,
        "errors": [],
        "http_ok": True,
        "cert_days": 60,
        "updates": {},
    }
    m.update(kw)
    return m


def test_instant_from_each_source():
    mail = mw.MailFindings(
        ndr_per_mailbox={"postmaster": 25},
        password_test_hits=1,
    )
    web = mw.diff_web(
        mw.parse_manifest("-rw-r--r-- 10 2026/01/01 00:00:00 keep.txt"),
        mw.parse_manifest(
            "\n".join([
                "-rw-r--r-- 10 2026/01/01 00:00:00 keep.txt",
                "-rw-r--r-- 10 2026/02/01 00:00:00 wp-content/mu-plugins/x/index.php",
            ])
        ),
    )
    dns = mw.diff_dns({"MX": ["10 a."]}, {"MX": ["10 b."]})
    report = mw.build_report(mail, web, dns, _meta())
    assert len(report.instant) >= 4
    assert all(
        t.startswith("Mrija: ") and b.startswith("Mrija: ")
        for t, b in report.instant
    )


def test_digest_at_most_six_lines():
    mail = mw.MailFindings(
        ndr_per_mailbox={"postmaster": 5, "admin": 2},
        risky_attach_total=3,
        spoof_spf_fail=1,
    )
    web = mw.WebFindings(digest_groups={"wp-content/plugins/elementor": 812})
    dns = mw.DnsFindings(changed=["TXT"])
    report = mw.build_report(
        mail, web, dns, _meta(errors=["rsync timeout"], http_ok=False, cert_days=9)
    )
    lines = [ln for ln in report.digest.splitlines() if ln.strip()]
    assert 1 <= len(lines) <= 6


def test_quiet_digest():
    report = mw.build_report(
        mw.MailFindings(), mw.WebFindings(), mw.DnsFindings(), _meta()
    )
    assert "ruhig" in report.digest


def test_digest_has_no_secrets():
    mail = mw.scan_mail(MAILDIR, {}, FakeGeoIP())
    report = mw.build_report(mail, mw.WebFindings(), mw.DnsFindings(), _meta())
    mw.assert_clean(report.digest, [PW_TOKEN])  # must not raise
    with pytest.raises(ValueError):
        mw.assert_clean(f"leak {PW_TOKEN} here", [PW_TOKEN])


# --- Task 6: collectors and run loop ---------------------------------------


def _stub(path, body, mode=0o755):
    path.write_text("#!/bin/sh\n" + body)
    path.chmod(mode)
    return str(path)


def test_rsync_failure_keeps_state(tmp_path, monkeypatch):
    rsync = tmp_path / "rsync"
    _stub(rsync, 'exit "${RSYNC_EXIT:-0}"\n')
    monkeypatch.setenv("RSYNC", str(rsync))
    monkeypatch.setenv("RSYNC_EXIT", "7")

    state_path = tmp_path / "state.json"
    manifest = "-rw-r--r-- 10 2026/01/01 00:00:00 index.php"
    mw.save_state(state_path, {"web_manifest": manifest})

    empty_maildir = tmp_path / "mail"
    empty_maildir.mkdir()
    cfg = {
        "state_path": state_path,
        "maildir": empty_maildir,
        "geoip": FakeGeoIP(),
        "remote": "x@host:www/",
        "keypath": "/dev/null",
        "ntfy_url": "http://127.0.0.1",
        "ntfy_topic": "mrija",
        "ntfy_token": "t",
    }
    meta = mw.run_collect(cfg)
    assert any("rsync" in e.lower() for e in meta["errors"])
    assert mw.load_state(state_path)["web_manifest"] == manifest


def test_post_ntfy_failure_returns_false(tmp_path, monkeypatch):
    curl = tmp_path / "curl"
    _stub(curl, "exit 7\n")
    monkeypatch.setenv("CURL", str(curl))
    assert mw.post_ntfy("http://127.0.0.1", "mrija", "t", "Mrija: x", "Mrija: y") is False
