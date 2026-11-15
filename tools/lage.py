#!/usr/bin/env python3
"""lage: a terminal view of what a Claude Code session is doing right now.

lage [--dir DIR] [--once]   follow the newest Claude session started in DIR
Everything is read from ~/.claude; nothing is written there.
"""
import argparse
import json
import os
import re
import shutil
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

MARKERS = (b'"type":"assistant"', b'"type":"user"', b'"type":"ai-title"')
# tool name -> (German verb, input key); keys ending in _path show the file name only
TOOLS = {
    "Bash": ("", "description"),
    "Read": ("liest ", "file_path"),
    "Edit": ("ändert ", "file_path"),
    "Write": ("ändert ", "file_path"),
    "MultiEdit": ("ändert ", "file_path"),
    "NotebookEdit": ("ändert ", "notebook_path"),
    "Grep": ("sucht ", "pattern"),
    "Glob": ("sucht ", "pattern"),
    "Agent": ("Helfer: ", "description"),
    "Task": ("Helfer: ", "description"),
}
HIGHLIGHT, RESET = "\x1b[1;7m", "\x1b[0m"
transcripts = {}  # sessionId -> Transcript, so each refresh reads only new bytes


def clean(s, limit):
    """First line only, control characters shown as ?, cut to limit with an ellipsis."""
    s = s.strip().split("\n", 1)[0].rstrip()
    s = re.sub("[\x00-\x1f\x7f-\x9f]", "?", s)
    # shortcut: counts characters, not terminal cells, so wide glyphs can overflow
    return s if len(s) <= limit else s[:limit - 1] + "…"


def clock():
    env = os.environ.get("LAGE_NOW")
    d = datetime.fromisoformat(env) if env else datetime.now(timezone.utc)
    return d if d.tzinfo else d.astimezone()


def parse_ts(s):
    d = datetime.fromisoformat(s)
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def cols():
    return shutil.get_terminal_size().columns


def short(path):
    home = str(Path.home())
    for prefix in (home + "/src/", home + "/"):
        if path.startswith(prefix):
            return path[len(prefix):]
    return path


def ago(seconds):
    seconds = max(int(seconds), 0)
    if seconds < 60:
        return f"{seconds} s"
    if seconds < 3600:
        return f"{seconds // 60} min"
    return f"{seconds // 3600} h"


def sessions():
    """Every session file with a sessionId, plus alive (its pid still has a /proc entry)."""
    found = []
    for f in (Path.home() / ".claude/sessions").glob("*.json"):
        try:
            d = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if isinstance(d, dict) and isinstance(d.get("sessionId"), str):
            pid = d.get("pid")
            d["alive"] = isinstance(pid, int) and Path(f"/proc/{pid}").exists()
            found.append(d)
    return found


def items(entry):
    """The content items of an entry's message, dicts only."""
    message = entry.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    return [i for i in content if isinstance(i, dict)] if isinstance(content, list) else []


class Transcript:
    def __init__(self, session_id):
        self.session_id = session_id
        self.path = None
        self.pos = 0
        self.last = None
        self.owner_ts = None
        self.title = None
        self.last_text = None

    def update(self):
        """Read the complete lines added since the last call."""
        if self.path is None:
            self.path = next(Path.home().glob(f".claude/projects/*/{self.session_id}.jsonl"), None)
        if self.path is None:
            return
        try:
            with self.path.open("rb") as f:
                f.seek(self.pos)
                for line in f:
                    if not line.endswith(b"\n"):
                        break  # still being written
                    self.pos += len(line)
                    if any(m in line for m in MARKERS):
                        self.take(line)
        except OSError:
            pass

    def take(self, line):
        try:
            e = json.loads(line)
        except ValueError:
            return
        if not isinstance(e, dict) or e.get("isSidechain"):
            return
        kind = e.get("type")
        if kind == "ai-title":
            if isinstance(e.get("aiTitle"), str):
                self.title = e["aiTitle"]
            return
        if kind not in ("assistant", "user"):
            return
        try:
            ts = parse_ts(e["timestamp"])
        except (KeyError, TypeError, ValueError):
            return
        origin = e.get("origin")
        if kind == "user" and isinstance(origin, dict) and origin.get("kind") == "human":
            self.owner_ts = ts
        for item in items(e) if kind == "assistant" else []:
            text = item.get("text")
            if item.get("type") == "text" and isinstance(text, str) and text.strip():
                self.last_text = clean(text, 10000)
        self.last = e

    def helpers(self):
        """Helpers of this session: no finished flag and a log written in the last 30 minutes."""
        if self.path is None:
            return 0
        count, n = 0, clock()
        for meta in (self.path.parent / self.session_id / "subagents").glob("agent-*.meta.json"):
            try:
                finished = json.loads(meta.read_text()).get("finished") is True
                log = meta.with_name(meta.name.removesuffix(".meta.json") + ".jsonl")
                age = (n - datetime.fromtimestamp(log.stat().st_mtime, timezone.utc)).total_seconds()
            except (OSError, ValueError, AttributeError):
                continue
            if not finished and age < 1800:
                count += 1
        return count


def tool_text(name, tool_input):
    verb, key = TOOLS.get(name, ("", ""))
    arg = tool_input.get(key)
    if key.endswith("_path") and isinstance(arg, str):
        arg = os.path.basename(arg)
    return verb + arg if isinstance(arg, str) and arg.strip() else name


def jetzt(tr, now):
    """The JETZT lines and a state: tool, denkt, wartet or helfer."""
    e = tr.last
    if e is None:
        return ["wartet auf dich"], "wartet"
    since = "seit " + ago((now - parse_ts(e["timestamp"])).total_seconds())
    message = e.get("message")
    stop = message.get("stop_reason") if isinstance(message, dict) else None
    tools = [i for i in items(e) if i.get("type") == "tool_use"]
    if e["type"] == "assistant" and tools:
        name = str(tools[-1].get("name") or "Tool")
        tool_input = tools[-1].get("input")
        text = tool_text(name, tool_input if isinstance(tool_input, dict) else {})
        lines, state = [text, f"{name} · {since}"], "tool"
    elif e["type"] == "assistant" and stop and stop != "tool_use":
        n = tr.helpers()
        if n:
            lines, state = [f"Helfer arbeiten ({n})", since], "helfer"
        else:
            lines, state = ["wartet auf dich", since], "wartet"
    else:
        lines, state = ["denkt nach", since], "denkt"
    return [clean(x, cols() - 8) for x in lines], state


def started(session):
    value = session.get("startedAt")
    return value if isinstance(value, (int, float)) else 0


def pick_by_dir(folder):
    """The newest live session started in folder or below it; else the newest dead one, ended."""
    folder = Path(os.path.abspath(folder))
    here = [s for s in sessions() if isinstance(s.get("cwd"), str) and Path(os.path.abspath(s["cwd"])).is_relative_to(folder)]
    for alive in (True, False):
        match = [s for s in here if s["alive"] == alive]
        if match:
            return max(match, key=started), not alive
    return None, False


def frame(session, ended, where):
    """The whole pane as lines. where finishes the sentence "kein Claude ", e.g. "in w"."""
    n, width = clock(), cols()
    stand = "Stand " + n.astimezone().strftime("%H:%M")
    left = "LAGE" if session is None else "LAGE  " + short(str(session.get("cwd")))
    left = clean(left, width - len(stand) - 1)
    out = [left + " " * (width - len(left) - len(stand)) + stand]
    if session is None:
        return out + [clean("kein Claude " + where, width)]
    state = ""
    if ended:
        lines = ["Sitzung beendet"]
    else:
        tr = transcripts.setdefault(session["sessionId"], Transcript(session["sessionId"]))
        tr.update()
        lines, state = jetzt(tr, n) if tr.path else (["Protokoll nicht gefunden"], "")
    if state == "wartet" and sys.stdout.isatty():
        lines[0] = HIGHLIGHT + lines[0] + RESET
    return out + ["JETZT ▶ " + lines[0]] + ["        " + x for x in lines[1:]]


def main():
    ap = argparse.ArgumentParser(prog="lage", description="Show what a Claude Code session is doing now.")
    ap.add_argument("--dir", default=os.getcwd(), help="follow the session started in this folder (default: cwd)")
    ap.add_argument("--once", action="store_true", help="print one frame and exit")
    args = ap.parse_args()
    where = "in " + short(os.path.abspath(args.dir))
    try:
        while True:
            session, ended = pick_by_dir(args.dir)
            lines = frame(session, ended, where)
            if args.once:
                print("\n".join(lines))
                return 0
            # home, then each line cleared to its end, then everything below: no flicker
            sys.stdout.write("\x1b[H" + "".join(x + "\x1b[K\n" for x in lines) + "\x1b[J")
            sys.stdout.flush()
            time.sleep(2)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
