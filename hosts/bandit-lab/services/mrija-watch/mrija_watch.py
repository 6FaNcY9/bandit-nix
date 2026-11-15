"""mrija-watch: daily protection watch for mrija.org.

Privacy rule (hard): notification text, the digest, journal lines and the
state file may contain only a mailbox name, a number, a 2-letter country
code, a rule name or a web path. Never a mail subject, body, attachment
filename or any third-party address.
"""

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path


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
