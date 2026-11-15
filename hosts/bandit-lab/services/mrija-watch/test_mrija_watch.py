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
