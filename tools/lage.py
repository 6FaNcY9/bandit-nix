#!/usr/bin/env python3
"""lage: a terminal view of what a Claude Code session is doing right now.

lage [--once]   follow the Claude session in the Cockpit master window (Hyprland); with --dir DIR the newest one started in DIR
lage [--dir DIR] --idea TEXT   add an owner idea to that session's board
lage --probe PID   exit 0 when a Claude session runs under the window with pid PID, else 1; no output
lage hook   Claude Code hook (JSON on stdin): tells a session its board and each new owner idea once
Everything is read from ~/.claude; nothing is written there. lage writes the board and, for the hook, a .shown file of hashes.
"""
import argparse
import hashlib
import json
import os
import re
import select
import shutil
import sys
import termios
import textwrap
import time
import tty
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import NamedTuple

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
HEADINGS = ("Funde", "Ungeprüft", "Für dich", "Deine Ideen")
IDEAS = HEADINGS[3]
LABS = ("re", "ctf", "live")
# - [ ] / [x] (ideas only), optional [YYYY-MM-DD ]H:MM, optional !, text
ENTRY = re.compile(
    r"-\s+(?:\[(?P<box>[ xX])\]\s+)?(?:(?P<stamp>(?:(?P<date>\d{4}-\d\d-\d\d)\s+)?(?P<hm>\d{1,2}:\d\d))\s+)?(?:(?P<bang>!)\s+)?(?P<text>.*)",
    re.ASCII,
)
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


def rows():
    return shutil.get_terminal_size().lines


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


def run(*cmd):
    """stdout of a command; empty when it is missing, fails or hangs."""
    import subprocess  # late: the hook does not need it and starts faster without
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL).stdout
    except (OSError, ValueError, subprocess.SubprocessError):
        return ""


def procs():
    """pid -> (parent pid, comm) of every process."""
    found = {}
    for f in Path("/proc").glob("[0-9]*/stat"):
        try:
            head, _, rest = f.read_text().rpartition(")")  # comm may hold spaces and brackets
            found[int(f.parent.name)] = (int(rest.split()[1]), head.partition("(")[2])
        except (OSError, ValueError, IndexError):
            pass
    return found


def master_pid():
    """Pid of the Cockpit master window: on the workspace of the window lage runs in, the visible, tiled window
    that is not the pane itself and sits furthest left (then top; master layout orientation left). None if unknown."""
    try:
        clients = [c for c in json.loads(run("hyprctl", "clients", "-j")) if isinstance(c, dict)]
    except (ValueError, TypeError):
        return None
    table, chain, p = procs(), [], os.getpid()
    while p in table and p not in chain:
        chain.append(p)
        p = table[p][0]
    own = next((c for p in chain for c in clients if c.get("pid") == p), None)

    def workspace(c):
        return (c.get("workspace") or {}).get("id")

    if own is None or workspace(own) is None:
        return None

    def candidate(c):
        shown = not c.get("floating") and not c.get("hidden") and c.get("class") != "cockpit-log"
        return shown and workspace(c) == workspace(own) and isinstance(c.get("at"), list) and len(c["at"]) == 2

    here = [c for c in clients if candidate(c)]
    return min(here, key=lambda c: c["at"])["pid"] if here else None


def claude_session_under(pid):
    """The session of the first claude process at or below pid. A tmux client below pid leads on to the processes
    of its tmux pane, which is where the session runs then."""
    table, known, kids = procs(), {s.get("pid"): s for s in sessions()}, {}
    for p, (parent, _) in sorted(table.items()):
        kids.setdefault(parent, []).append(p)

    def below(root):  # root and everything under it, nearest first
        order = [root]
        for p in order:
            order += [k for k in kids.get(p, []) if k not in order]
        return order

    def comm(p):
        return table.get(p, (0, ""))[1]

    def find(root):
        return next((known[p] for p in below(root) if comm(p) == "claude" and p in known), None)

    if (found := find(pid)) is None:
        for p in below(pid):
            if not comm(p).startswith("tmux"):
                continue
            # tmux is not on every PATH, but the client in the window is the tmux binary itself
            listing = run(shutil.which("tmux") or f"/proc/{p}/exe", "list-clients", "-F", "#{client_pid} #{pane_pid}")
            for client, pane in re.findall(r"^(\d+) (\d+)$", listing, re.M | re.A):
                if int(client) == p and (found := find(int(pane))):
                    return found
    return found


def master_session(previous):
    """(session, ended) for the master window: the session in it; else the previous one, ended; else (None, False)."""
    pid = master_pid()
    session = claude_session_under(pid) if pid is not None else None
    return (session, False) if session or previous is None else (previous, True)


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


def sitzungen_lines(followed_sid, cols):
    """SITZUNGEN: a line per running session, waiting ones first (!), then by name; the followed one is marked ▶."""
    now, rows = clock(), []
    for s in sessions():
        if not s["alive"]:
            continue
        sid = s["sessionId"]
        tr = transcripts.setdefault(sid, Transcript(sid))
        tr.update()
        state = jetzt(tr, now)[1]
        name = s.get("name")
        name = (clean(name, 12) if isinstance(name, str) else "") or clean(sid[:6], 6)
        if state == "wartet":
            mark, text = "!", "wartet: " + tr.last_text if tr.last_text else "wartet"
        else:
            mark, text = "▶" if sid == followed_sid else " ", "Helfer arbeiten" if state == "helfer" else "arbeitet"
        rows.append((mark, name, sid, clean(tr.title, 12) if tr.title else "", text))
    if not rows:
        return []
    rows.sort(key=lambda r: (r[0] != "!", r[1], r[2]))
    shown = rows[:6]
    nw, tw = max(len(r[1]) for r in shown), max(len(r[3]) for r in shown)
    out = ["SITZUNGEN"]
    for mark, name, _, topic, text in shown:
        line = f" {mark}  {name:<{nw}}  {topic:<{tw}}  {text}"
        out.append(line if len(line) <= cols else line[:cols - 1] + "…")
    return out + ([f"+{len(rows) - 6} weitere"] if len(rows) > 6 else [])


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


class Entry(NamedTuple):
    ts: datetime | None  # local time as written on the board, naive
    important: bool
    done: bool | None  # None outside Deine Ideen
    text: str


def board_path(session_id, start_cwd):
    """<lab folder>/.claude/lage.md for a start folder inside ~/src/sec/{re,ctf,live}/<name>/, else a file in ~/.local/state/lage."""
    home, here = Path.home(), Path(os.path.abspath(start_cwd))
    for kind in LABS:
        base = home / "src/sec" / kind
        if here.is_relative_to(base) and here != base:
            return base / here.relative_to(base).parts[0] / ".claude/lage.md"
    return home / ".local/state/lage" / (session_id + ".md")


def heading(line):
    m = re.match(r"#+\s*(.*)", line.strip())
    return m.group(1).strip() if m else None


def parse_board(text, today):
    """Entries by section. Unknown headings, lines before the first heading and lines that are no entry are dropped."""
    board = {h: [] for h in HEADINGS}
    section = None
    for line in text.splitlines():
        name = heading(line)
        if name is not None:
            section = name if name in board else None
            continue
        m = ENTRY.match(line.strip())
        if section is None or not m:
            continue
        body = clean(m["text"], 500)
        ts = None
        if m["stamp"]:
            try:
                ts = datetime.fromisoformat(f"{m['date'] or today.isoformat()}T{m['hm'].zfill(5)}")
            except ValueError:
                body = clean(m["stamp"] + " " + body, 500)  # not a time after all
        if body:
            done = m["box"] in ("x", "X") if section == IDEAS else None
            board[section].append(Entry(ts, bool(m["bang"]), done, body))
    return board


def add_idea(path, text, now):
    """Append '- [ ] YYYY-MM-DD HH:MM text' as the last line of Deine Ideen; the rest of the file stays as it is."""
    text = clean(text, 200)
    if not text:
        return
    try:
        with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:  # newline="": keep CRLF
            old = f.read()
    except FileNotFoundError:
        old = "".join(f"## {h}\n" for h in HEADINGS)
    lines = (old if old.endswith("\n") or not old else old + "\n").split("\n")[:-1]
    new = f"- [ ] {now.astimezone():%Y-%m-%d %H:%M} {text}"
    start = next((i for i, x in enumerate(lines) if heading(x) == IDEAS), None)
    if start is None:
        lines += ["## " + IDEAS, new]
    else:
        end = start + 1
        while end < len(lines) and heading(lines[end]) is None:
            end += 1
        while end > start + 1 and not lines[end - 1].strip():
            end -= 1  # blank lines before the next heading stay below the idea
        lines.insert(end, new)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_text("\n".join(lines) + "\n", encoding="utf-8", errors="surrogateescape")
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def board_lines(board, owner_ts, cols, rows):
    """The four sections: head, newest entries that fit, then one +N ältere line."""
    today = clock().astimezone().date()
    cut = owner_ts.astimezone().replace(tzinfo=None, second=0, microsecond=0) if owner_ts else None
    space = max(2, (rows - 19) // 4)
    lit = sys.stdout.isatty()

    def neu(e):
        return cut is not None and e.done is None and e.ts is not None and e.ts >= cut

    out = []
    for h in HEADINGS:
        # open ideas first, then newest first, entries without a time last
        entries = sorted(board.get(h, []), key=lambda e: (bool(e.done), e.ts is None, datetime.max - e.ts if e.ts else timedelta()))
        n = sum(map(neu, entries))
        if h == IDEAS:
            out.append(f"{h.upper()}  {sum(not e.done for e in entries)} offen")
        else:
            out.append(f"{h.upper()}  {len(entries)}" + (f"  ({n} neu)" if n else ""))
        used = shown = 0
        for e in entries:
            when = "     " if e.ts is None else e.ts.strftime("%H:%M" if e.ts.date() == today else "%d.%m.")
            head = f"{'NEU ' if neu(e) else '    '}{'!' if e.important else '·'}  {when} "
            text = e.text if e.done is None else ("[x] " if e.done else "[ ] ") + e.text
            wrapped = textwrap.wrap(text, max(cols - len(head), 1))
            lines = [head + wrapped[0]] + [" " * len(head) + x for x in wrapped[1:]]
            if used + len(lines) > space:
                if used:
                    break
                lines = lines[:space]  # even the newest entry never gets more than its share
                lines[-1] = lines[-1][:-1] + "…"
            out += [HIGHLIGHT + x + RESET for x in lines] if lit and e.important else lines
            used += len(lines)
            shown += 1
        if shown < len(entries):
            out.append(f"+{len(entries) - shown} ältere")
    return out


def board_of(session):
    return board_path(session["sessionId"], str(session.get("cwd")))


def frame(session, ended, where):
    """The whole pane as lines. where finishes the sentence "kein Claude ", e.g. "in w"."""
    n, width = clock(), cols()
    stand = "Stand " + n.astimezone().strftime("%H:%M")
    left = "LAGE" if session is None else "LAGE  " + short(str(session.get("cwd")))
    left = clean(left, width - len(stand) - 1)
    out = [left + " " * (width - len(left) - len(stand)) + stand]
    if session is None:
        return out + [clean("kein Claude " + where, width)]
    state, owner_ts = "", None
    if ended:
        lines = ["Sitzung beendet"]
    else:
        tr = transcripts.setdefault(session["sessionId"], Transcript(session["sessionId"]))
        tr.update()
        lines, state = jetzt(tr, n) if tr.path else (["Protokoll nicht gefunden"], "")
        owner_ts = tr.owner_ts
    if state == "wartet" and sys.stdout.isatty():
        lines[0] = HIGHLIGHT + lines[0] + RESET
    try:
        text = board_of(session).read_text(encoding="utf-8", errors="replace")
    except OSError:
        text = ""
    rule = "─" * width
    out += ["JETZT ▶ " + lines[0]] + ["        " + x for x in lines[1:]] + [rule]
    out += board_lines(parse_board(text, n.astimezone().date()), owner_ts, width, rows()) + [rule]
    block = sitzungen_lines(session["sessionId"], width)
    return out + (block + [rule] if block else []) + ["i = Idee eintragen"]


def wait(seconds, session):
    """Sleep. On a terminal, the key i asks for an idea and adds it to the board; other keys do nothing."""
    if not sys.stdin.isatty():
        time.sleep(seconds)
        return
    fd, saved = sys.stdin.fileno(), termios.tcgetattr(sys.stdin.fileno())
    key, end = b"", time.monotonic() + seconds
    try:
        tty.setcbreak(fd, termios.TCSANOW)
        while key != b"i" and (left := end - time.monotonic()) > 0:
            if select.select([fd], [], [], left)[0]:
                key = os.read(fd, 1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    if key == b"i" and session is not None:
        try:
            add_idea(board_of(session), input("Idee: "), clock())
        except (EOFError, KeyboardInterrupt, OSError):
            pass  # cancelled, or the board is not writable: the next refresh shows no new idea


def hook():
    """Claude Code hook on SessionStart, UserPromptSubmit and PostToolUse. Prints JSON for Claude only when there is
    something to say (the board path on SessionStart, each new open owner idea once). Never creates the board; always 0."""
    try:
        data = json.load(sys.stdin)
        sid, event = data["session_id"], data["hook_event_name"]
        if "agent_id" in data or not re.fullmatch(r"[0-9a-f-]{8,}", sid):
            return 0  # a helper, or an id that must not become a file name
        start = next((s["cwd"] for s in sessions() if s["sessionId"] == sid and isinstance(s.get("cwd"), str)), data.get("cwd"))
        path = board_path(sid, start)
        lines = ["Lage-Board: " + str(path)] if event == "SessionStart" else []
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        shown_file = Path.home() / ".local/state/lage" / (sid + ".shown")  # hashes only: lab text stays in its lab folder
        try:
            shown = shown_file.read_text().split()
        except OSError:
            shown = []
        # shortcut: ideas with the same text count as one, because only the hash of the line is kept; upgrade if that bites
        new = {}
        for e in parse_board(text, clock().astimezone().date())[IDEAS]:
            line = "Neue Idee von vino: " + e.text
            digest = hashlib.sha256(line.encode()).hexdigest()
            if e.done is False and digest not in shown:
                new[digest] = line
        if new:
            shown_file.parent.mkdir(parents=True, exist_ok=True)
            with shown_file.open("a") as f:
                f.writelines(d + "\n" for d in new)
            lines += new.values()
        if lines:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": "\n".join(lines)}}))
    except Exception:  # a hook must never break the session it watches
        pass
    return 0


def main():
    if sys.argv[1:] == ["hook"]:
        return hook()
    ap = argparse.ArgumentParser(prog="lage", description="Show what a Claude Code session is doing now.")
    ap.add_argument("--dir", help="follow the newest session started in this folder (default: the Cockpit master window)")
    ap.add_argument("--once", action="store_true", help="print one frame and exit")
    ap.add_argument("--idea", metavar="TEXT", help="add an idea to the board of the followed session and exit")
    ap.add_argument("--probe", type=int, metavar="PID", help="exit 0 if a Claude session runs under the window with this pid, else 1")
    args = ap.parse_args()
    if args.probe is not None:
        return 0 if claude_session_under(args.probe) else 1
    where = "im Hauptfenster" if args.dir is None else "in " + short(os.path.abspath(args.dir))

    def pick(previous):
        return master_session(previous) if args.dir is None else pick_by_dir(args.dir)

    if args.idea is not None:
        session, _ = pick(None)
        if session is None:
            print("lage: kein Claude " + where, file=sys.stderr)
            return 1
        try:
            add_idea(board_of(session), args.idea, clock())
        except OSError as e:
            print("lage:", e, file=sys.stderr)
            return 1
        return 0
    session = None
    try:
        while True:
            session, ended = pick(session)
            lines = frame(session, ended, where)
            if args.once:
                print("\n".join(lines))
                return 0
            # home, then each line cleared to its end, then everything below: no flicker
            sys.stdout.write("\x1b[H" + "".join(x + "\x1b[K\n" for x in lines) + "\x1b[J")
            sys.stdout.flush()
            wait(2, session)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
