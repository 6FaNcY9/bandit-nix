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
