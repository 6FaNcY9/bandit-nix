import json
from pathlib import Path

import mrija_watch as mw


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
