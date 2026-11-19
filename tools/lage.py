"""lage: a terminal view of what a Claude Code session is doing right now.

lage [--once] [--full]   follow the Claude session in the Cockpit master window (Hyprland); with --dir DIR the newest one
  started in DIR. The main view is a short overview; --full (or the key f) shows the whole board.
lage [--dir DIR] --idea TEXT   add an owner idea to that session's board
lage --probe PID   exit 0 when a Claude session runs under the window with pid PID, else 1; no output
lage bar [--focus]   Waybar: one JSON line with busy/waiting session counts; --focus jumps to the waiting session
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

MARKERS = (b'"type":"assistant"', b'"type":"user"', b'"type":"ai-title"', b'"type":"custom-title"')
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
    "WebFetch": ("liest eine Webseite", ""),
    "WebSearch": ("sucht im Web", ""),
}
HIGHLIGHT, RED, RESET = "\x1b[1;7m", "\x1b[1;31m", "\x1b[0m"
TEAL, YELLOW, DIM = "\x1b[1;36m", "\x1b[1;33m", "\x1b[2m"  # the theme's own ANSI colours
GREY = "\x1b[90m"  # kitty color8 = base02 #303034: the overview's rules
MEMORY = ("basic-memory", "firma")  # MCP servers shown as Gedächtnis
BOARD = re.compile(r"lage\.md|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.md")
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
    that is not the pane itself and sits furthest left (then top; master layout orientation left), among tabs of a
    group the one focused last. None if unknown."""
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
    # tabs of a group share `at` and none is hidden: the most recently focused one (lowest focusHistoryID) is on top
    return min(here, key=lambda c: (c["at"], c.get("focusHistoryID", 0)))["pid"] if here else None


def store_tmux(path):
    """path resolved, if it is a tmux binary in the Nix store; else None. lage runs it, so a process that merely calls
    itself tmux must not get that far."""
    real = os.path.realpath(path)
    return real if real.startswith("/nix/store/") and os.path.basename(real) == "tmux" else None


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
            if (exe := shutil.which("tmux") or store_tmux(f"/proc/{p}/exe")) is None:
                continue
            listing = run(exe, "list-clients", "-F", "#{client_pid} #{pane_pid}")
            for client, pane in re.findall(r"^(\d+) (\d+)$", listing, re.M | re.A):
                if int(client) == p and (found := find(int(pane))):
                    return found
    return found


def master_session(previous):
    """(session, ended) for the master window: the session in it; else (None, False), or, when the previous session is
    gone (its file or its process), (previous, True). A master window that shows something else ends nothing."""
    pid = master_pid()
    session = claude_session_under(pid) if pid is not None else None
    if session or previous is None:
        return session, False
    gone = not any(s["sessionId"] == previous["sessionId"] and s["alive"] for s in sessions())
    return (previous, True) if gone else (None, False)


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
        self.settled = None  # like last, for a session file without status: entries that are no turn leave it alone
        self.owner_ts = None
        self.last_text = None
        self.titles = {}  # the tab title: "custom-title" (/rename) beats "ai-title"

    def locate(self):
        """The transcript file once it exists, else None."""
        if self.path is None:
            self.path = next(Path.home().glob(f".claude/projects/*/{self.session_id}.jsonl"), None)
        return self.path

    def tail(self, nbytes=262144):
        """The first read of a big file starts nbytes before its end, at a line start; a tail without a settled entry reads it all."""
        if self.pos or self.locate() is None:
            return
        try:
            with self.path.open("rb") as f:
                size = f.seek(0, os.SEEK_END)
                if size > nbytes:
                    f.seek(size - nbytes - 1)  # one byte early: a line that starts exactly at the cut stays whole
                    f.readline()
                    self.pos = f.tell()
        except OSError:
            return
        self.update()
        if self.settled is None and self.pos:  # settled is None whenever last is; jetzt() reads either one
            self.__init__(self.session_id)
            self.update()

    def update(self):
        """Read the complete lines added since the last call."""
        if self.locate() is None:
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
        title = e.get("customTitle" if kind == "custom-title" else "aiTitle")
        if kind in ("ai-title", "custom-title") and isinstance(title, str):
            self.titles[kind] = title
        if kind not in ("assistant", "user"):
            return
        try:
            ts = parse_ts(e["timestamp"])
        except (KeyError, TypeError, ValueError):
            return
        origin = e.get("origin")
        if kind == "user" and isinstance(origin, dict) and origin.get("kind") == "human":
            self.owner_ts, self.last_text = ts, None  # the owner answered: an earlier question is not waited on any more
        for item in items(e) if kind == "assistant" else []:
            text = item.get("text")
            if item.get("type") == "text" and isinstance(text, str) and text.strip():
                self.last_text = clean(text, 10000)
        self.last = e
        if kind == "assistant" or "origin" in e or any(i.get("type") == "tool_result" for i in items(e)):
            self.settled = e
        elif any(str(i.get("text")).startswith("[Request interrupted by user") for i in items(e)):
            self.settled = {**e, "type": "assistant", "message": {"stop_reason": "interrupt"}}  # the turn is over

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
    """A tool call in short German; a name nobody can read (MCP tools, the board's file name) gets a plain one."""
    if name.startswith("mcp__"):
        server, _, tool = name[5:].partition("__")
        if server in MEMORY:
            return "schreibt ins Gedächtnis" if tool in ("bm_edit", "bm_write", "bm_delete", "bm_move") else "liest im Gedächtnis"
        return "Werkzeug " + server
    verb, key = TOOLS.get(name, ("", ""))
    if not key:
        return verb or name
    arg = tool_input.get(key)
    if key.endswith("_path") and isinstance(arg, str):
        arg = os.path.basename(arg)
        arg = "das Board" if BOARD.fullmatch(arg) else arg
    return verb + arg if isinstance(arg, str) and arg.strip() else name


def waiting_for(s):
    """What a waiting session waits for, as its session file says; empty otherwise."""
    w = s.get("waitingFor")
    return clean(w, 40) if s.get("status") == "waiting" and isinstance(w, str) else ""


def jetzt(tr, now, s):
    """The ▶ line (in a list) and a state: tool, denkt, wartet or helfer. The status in the session file s wins
    where it says waiting or idle; busy, shell, any other status and a missing one leave it to the transcript."""
    status = s.get("status")
    e = tr.last if status else tr.settled
    since = "seit " + ago((now - parse_ts(e["timestamp"])).total_seconds()) if e else ""
    if status == "waiting":
        text, state = "wartet auf dich" + (": " + waiting_for(s) if waiting_for(s) else ""), "wartet"
    elif e is None:
        text, state = "wartet auf dich", "wartet"
    else:
        message = e.get("message")
        stop = message.get("stop_reason") if isinstance(message, dict) else None
        tools = [i for i in items(e) if i.get("type") == "tool_use"]
        idle = status == "idle"
        if e["type"] == "assistant" and tools and not idle:
            tool_input = tools[-1].get("input")
            text, state = tool_text(str(tools[-1].get("name") or "Tool"), tool_input if isinstance(tool_input, dict) else {}), "tool"
        elif idle or (e["type"] == "assistant" and stop and stop != "tool_use"):
            n = tr.helpers()
            text, state = (f"Helfer arbeiten ({n})", "helfer") if n else ("wartet auf dich", "wartet")
        else:
            text, state = "denkt nach", "denkt"
    return [clean(f"{text}  {since}" if since else text, cols() - 2)], state


def label(s, tr):
    """The name a session goes by: its tab title, else its name, else the start of its id."""
    name = s.get("name")
    title = tr.titles.get("custom-title") or tr.titles.get("ai-title")
    return clean(title or "", 18) or (clean(name, 12) if isinstance(name, str) else "") or clean(s["sessionId"][:6], 6)


def session_state(s):
    """(state, since, line) of a session: jetzt()'s state, the time of the entry it rests on (None without one), its ▶ line."""
    tr = transcripts.setdefault(s["sessionId"], Transcript(s["sessionId"]))
    tr.tail()
    lines, state = jetzt(tr, clock(), s)
    e = tr.last if s.get("status") else tr.settled
    return state, parse_ts(e["timestamp"]) if e else None, lines[0]


def bar_json():
    """One Waybar JSON line: counts of busy (●) and waiting (▲) live sessions, a tooltip with one line each. Empty: no session."""
    now, rows = clock(), []
    for s in sessions():
        if s["alive"]:
            state, since, line = session_state(s)
            rows.append((state == "wartet", since or now, f"{'▲' if state == 'wartet' else '●'} {label(s, transcripts[s['sessionId']])}: {line}"))
    waiting = sum(r[0] for r in rows)
    parts = [f"{sym} {n}" for sym, n in (("●", len(rows) - waiting), ("▲", waiting)) if n]
    if not parts:
        return {"text": ""}
    return {"text": " ".join(parts), "class": "waiting" if waiting else "busy", "tooltip": "\n".join(r[2] for r in sorted(rows, key=lambda r: (not r[0], r[1])))}


def bar_focus():
    """Focus the window of the live session that waits longest, else of the one busy longest. 0 when focused, 1 when no
    session or no window matched."""
    now, rows = clock(), []
    for s in sessions():
        if s["alive"]:
            state, since, _ = session_state(s)
            rows.append((state != "wartet", since or now, s["sessionId"]))
    return focus(min(rows)[2]) if rows else 1


def jump():
    """Enter in the view: focus the window of the session that waits longest for the owner, else of the one working
    longest; a resting one never (states(), unlike bar_focus(), does not take idle for waiting). 0 when focused, else 1."""
    now = clock()
    rows = [(state != "wartet", since or now, s["sessionId"]) for s, state, since, _ in states() if state != "ruht"]
    return focus(min(rows)[2]) if rows else 1


def focus(target):
    """Focus the window whose Claude session has the id target. 0 when focused, 1 when no window matched. Probes down
    from each window only: walking up from a tmux pane never reaches one."""
    try:
        clients = [c for c in json.loads(run("hyprctl", "clients", "-j")) if isinstance(c, dict)]
    except (ValueError, TypeError):
        return 1
    for c in clients:
        if isinstance(c.get("pid"), int) and isinstance(c.get("address"), str):
            found = claude_session_under(c["pid"])
            if found and found["sessionId"] == target:
                run("hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{c["address"]}" }})')  # also makes a group tab active
                return 0
    return 1


def wartet_lines(followed_sid, cols):
    """A line per other session that waits for the owner: its tab title (else its name) and what it waits for. More
    than 3: the first 2 and a +N weitere line."""
    now, rows = clock(), []
    for s in sessions():
        sid = s["sessionId"]
        if not s["alive"] or sid == followed_sid:
            continue
        tr = transcripts.setdefault(sid, Transcript(sid))
        tr.update()
        if jetzt(tr, now, s)[1] != "wartet":
            continue
        name = label(s, tr)
        why = waiting_for(s) or tr.last_text
        rows.append((name, sid, clean(f"! {name} wartet" + (": " + why if why else ""), cols)))
    lines = [r[2] for r in sorted(rows)]
    return lines if len(lines) <= 3 else lines[:2] + [f"+{len(lines) - 2} weitere"]


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


def cut_of(since):
    """The NEU limit as board time (local, naive, whole minute): entries from that minute on are new."""
    return since.astimezone().replace(tzinfo=None, second=0, microsecond=0) if since else None


def is_new(e, cut, seen=frozenset()):
    """Newer than the owner's last prompt (cut) and not yet seen in the full view."""
    return cut is not None and e.done is None and e.ts is not None and e.ts >= cut and e not in seen


def paint(code, s, lit):
    return code + s + RESET if lit else s


def board_lines(board, since, cols, space, seen=frozenset()):
    """The four sections: head, newest entries that fit in space lines, then one +N ältere line."""
    today = clock().astimezone().date()
    cut = cut_of(since)
    lit = sys.stdout.isatty()

    def neu(e):
        return is_new(e, cut, seen)

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


def board_entries(session):
    """Every entry on the session's board now; empty without a session or a readable board."""
    try:
        text = board_of(session).read_text(encoding="utf-8", errors="replace") if session else ""
    except OSError:
        text = ""
    return frozenset(e for x in parse_board(text, clock().astimezone().date()).values() for e in x)


def states():
    """(session, state, since, text) per live session, oldest start first. state: wartet (only a status waiting), helfer,
    arbeitet (jetzt()'s tool or denkt, or a status busy) or ruht; text: jetzt()'s step for arbeitet and helfer, else
    empty. Unlike jetzt(), idle and a finished turn are ruht here: only the status proves that a session waits."""
    out = []
    for s in sorted((s for s in sessions() if s["alive"]), key=lambda s: (started(s), s["sessionId"])):
        transcripts.setdefault(s["sessionId"], Transcript(s["sessionId"])).update()  # session_state() alone tails only once
        kind, since, line = session_state(s)
        cut = line.rfind("  seit ")
        text = line[:cut] if cut > 0 else line
        if s.get("status") == "waiting":
            state = "wartet"
        elif kind == "helfer":
            state = "helfer"
        else:
            state = "arbeitet" if kind in ("tool", "denkt") or s.get("status") == "busy" else "ruht"
        out.append((s, state, since, text if kind in ("tool", "denkt", "helfer") else ""))
    return out


def du_lines(live, width, most=3):
    """DU: the owner's next steps in a fixed order: liefern's queue, the sessions waiting for him (longest first), the
    open ! lines under Für dich (no → yet) on the boards of live sessions, newest first and cut at the first ": " or
    ". " when the part before it has at least 2 words. At most `most` steps; the rest is counted, so a ! line is never
    dropped silently."""
    lit, steps = sys.stdout.isatty(), []
    queued = len(list((Path.home() / ".local/state/liefern/warten").glob("*.eintrag")))  # tools/liefern's queue
    if queued:
        steps.append((YELLOW, f"liefern · {queued} {'wartet' if queued == 1 else 'warten'}"))
    for s, _, _, _ in sorted((x for x in live if x[1] == "wartet"), key=lambda x: x[2] or clock()):
        why = waiting_for(s)
        steps.append((YELLOW, f"▲ {label(s, transcripts[s['sessionId']])} wartet auf dich" + (": " + why if why else "")))
    today, bangs = clock().astimezone().date(), []
    for path in dict.fromkeys(board_of(s) for s, *_ in live):  # sessions in one lab folder share its board
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        bangs += [e for e in parse_board(text, today)["Für dich"] if e.important and "→" not in e.text]
    bangs.sort(key=lambda e: (e.ts is None, datetime.max - e.ts if e.ts else timedelta()))
    for e in bangs:
        head = re.split(r": |\. ", e.text, maxsplit=1)[0]
        steps.append((RED, head if len(head.split()) >= 2 else e.text))  # a one-word head ("Handy", "Dr", "z") says too little
    if not steps:
        return [paint(DIM, " " + clean("DU  nichts offen", width - 1), lit)]
    out = [paint(YELLOW, " DU", lit)]
    out += [paint(code, " " + clean(f"{i}  {text}", width - 1), lit) for i, (code, text) in enumerate(steps[:most], 1)]
    return out + ([paint(DIM, "    " + clean(f"+{len(steps) - most} weitere", max(width - 4, 1)), lit)] if len(steps) > most else [])


def session_rows(live, width):
    """One line per live session of states(): ● arbeitet with its step, ▲ wartet auf dich, ● Helfer, ○ ruht with its age."""
    lit, now, out = sys.stdout.isatty(), clock(), []
    for s, state, since, text in live:
        age = ago((now - since).total_seconds()) if since else ""
        sym, code, rest = {
            "wartet": ("▲", YELLOW, "wartet auf dich  " + age),
            "helfer": ("●", TEAL, text),
            "arbeitet": ("●", TEAL, "arbeitet  " + text),
            "ruht": ("○", DIM, "ruht  " + age),
        }[state]
        out.append(paint(code, " " + clean(f"{sym} {label(s, transcripts[s['sessionId']])}  {rest}", width - 1), lit))
    return out or [paint(DIM, " keine Sitzung", lit)]


def news_lines(live, width):
    """NEU: the newest Fund of each live session, one per board (sessions in one lab folder share it), in the order of
    the rows: as a pair, its time (DD.MM. on another day) and label, below it the text. Unreadable boards are skipped."""
    lit, today, boards, out = sys.stdout.isatty(), clock().astimezone().date(), {}, []
    for s, *_ in live:
        boards.setdefault(board_of(s), s)
    for path, s in boards.items():
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        e = max((e for e in parse_board(text, today)["Funde"] if e.ts), key=lambda e: e.ts, default=None)
        if e:
            when = f"{e.ts:%H:%M}" if e.ts.date() == today else f"{e.ts:%d.%m.}"
            out.append((paint(TEAL, " " + clean(f"{when}  {label(s, transcripts[s['sessionId']])}", width - 1), lit),
                        "    " + clean(e.text, max(width - 4, 1))))
    return out


def delivered_lines(width, most=3):
    """GELIEFERT heute (N): the newest `most` of today's done liefern entries, the time from the file name
    (fertig/YYYY-MM-DD-HHMM-<name>.eintrag), the owner's sentence from its second line; [] without one to show."""
    lit, day = sys.stdout.isatty(), clock().astimezone().strftime("%Y-%m-%d")
    done = sorted((Path.home() / ".local/state/liefern/fertig").glob(day + "-*.eintrag"), reverse=True)
    rows = []
    for f in done[:most]:
        try:
            said = (f.read_text(encoding="utf-8", errors="replace").split("\n") + ["", ""])[1]
        except OSError:
            continue
        hm = f.name[len(day) + 1:len(day) + 5]
        if said.strip():
            rows.append(paint(DIM, " " + clean(f"{hm[:2]}:{hm[2:]}  {said}", width - 1), lit))
    return [paint(DIM, " " + clean(f"GELIEFERT heute ({len(done)})", width - 1), lit)] + rows if rows else []


def usage():
    """[5 h N %, Woche N %] from claude-hud's usage snapshot, each only while it is a number; [] when unreadable."""
    try:
        u = json.loads((Path.home() / ".cache/claude-hud/usage.json").read_text())
        found = [(name, (u.get(key) or {}).get("used_percentage")) for name, key in (("5 h", "five_hour"), ("Woche", "seven_day"))]
        return [f"{name} {round(p)} %" for name, p in found if type(p) in (int, float)]
    except (OSError, ValueError, OverflowError, AttributeError):
        return []  # missing, no JSON, or not shaped like claude-hud's snapshot: no numbers


def foot_line(width, keys):
    """The keys (f and i only with a followed session), on the right usage() when it fits, else its last part (the week)."""
    left, parts = " f alles   i Idee   ⏎ zur Sitzung" if keys else " ⏎ zur Sitzung", usage()
    for right in (" · ".join(parts), parts[-1] if parts else ""):
        if right and len(left) + len(right) < width:
            return paint(DIM, left + " " * (width - len(left) - len(right)) + right, sys.stdout.isatty())
    return paint(DIM, left[:width], sys.stdout.isatty())


def frame(session, ended, where, full=False, seen=frozenset()):
    """The whole pane as lines, at most one fewer than the pane is high (the newline after the last would scroll it).
    where finishes the sentence "kein Claude ", e.g. "in w". full: the session's whole board instead of the overview.
    seen: the entries the owner saw when last closing the full view of this session; they are no longer NEU."""
    n, width, room = clock(), cols(), max(rows() - 1, 1)
    lit = sys.stdout.isatty()
    stand = n.astimezone().strftime("%H:%M")
    left = "LAGE" if session is None else "LAGE  " + short(str(session.get("cwd")))
    left = clean(left, width - len(stand) - 1)
    head = [paint(TEAL, "LAGE", lit) + left[4:] + " " * (width - len(left) - len(stand)) + paint(DIM, stand, lit)]
    rule = "─" * width
    if session is None or not full:
        # Overview, also without a session: head, DU, the sessions between two rules, the keys. A small pane drops the
        # rules first, then the keys, then the sessions that do not fit (counted); DU folds its steps into its +N line.
        head += [clean("kein Claude " + where, width)] if session is None else ["Sitzung beendet"] if ended else []
        live = states()
        free = room - len(head)
        du = du_lines(live, width, max(min(3, free - 2), 0))
        free -= len(du)
        sess = session_rows(live, width)
        if len(sess) > free:
            keep = max(free - 1, 0)
            sess = sess[:keep] + [paint(DIM, "   " + clean(f"+{len(sess) - keep} weitere Sitzungen", max(width - 3, 1)), lit)] if free > 0 else []
        free -= len(sess)
        foot = [foot_line(width, session is not None)] if free > 0 else []
        sep = [paint(GREY, rule, lit)] if free - len(foot) >= 2 else []
        # The rows left after all that, each block with its rule below: NEU in whole pairs, then GELIEFERT with a row.
        left, more = free - len(foot) - 2 * len(sep), []
        if sep:
            pairs = news_lines(live, width)[:max((left - 2) // 2, 0)]
            if pairs:
                more += [paint(TEAL, " NEU", lit)] + [x for p in pairs for x in p] + sep
                left -= 2 + 2 * len(pairs)
            done = delivered_lines(width, max(min(3, left - 2), 0))
            if done and len(done) < left:
                more += done + sep
        return (head + du + sep + sess + sep + more + foot)[:room]
    wartet = [paint(RED if x.startswith("!") else DIM, x, lit) for x in wartet_lines(session["sessionId"], width)]
    state, since = "", None
    if ended:
        line = "Sitzung beendet"
    else:
        tr = transcripts.setdefault(session["sessionId"], Transcript(session["sessionId"]))
        tr.update()
        line, state = jetzt(tr, n, session) if tr.path else (["Protokoll nicht gefunden"], "")
        line, since = line[0], tr.owner_ts
    cut = line.rfind("  seit ")
    text, age = (line[:cut], line[cut:]) if cut > 0 else (line, "")
    line = paint(YELLOW, "▶ " + text, lit and state == "wartet") + (paint(DIM, age, lit) if age else "")
    try:
        text = board_of(session).read_text(encoding="utf-8", errors="replace")
    except OSError:
        text = ""
    board = parse_board(text, n.astimezone().date())
    top = head + [line] + wartet
    foot = [rule, "i = Idee   f = zurück"]
    free = room - len(top) - 1 - len(foot)
    # lines per section: what is left, less the 4 headings and the 4 +N ältere lines; a pane too small for it loses
    # the end of the board first, then the end of the foot
    body = board_lines(board, since, width, max(1, (free - 8) // 4), seen)
    return (top + [rule] + body[:max(free, 0)] + foot)[:room]


def wait(seconds, session):
    """Sleep. On a terminal, the key i asks for an idea and adds it to the board, f ends the wait at once, Enter jumps to
    the session that needs the owner (jump()); other keys do nothing. Returns the key that ended the wait, b"i" or b"f",
    else b""."""
    if not sys.stdin.isatty():
        time.sleep(seconds)
        return b""
    fd, saved = sys.stdin.fileno(), termios.tcgetattr(sys.stdin.fileno())
    key, end = b"", time.monotonic() + seconds
    try:
        tty.setcbreak(fd, termios.TCSANOW)
        while key not in (b"i", b"f", b"\r", b"\n") and (left := end - time.monotonic()) > 0:
            if select.select([fd], [], [], left)[0]:
                key = os.read(fd, 1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    if key in (b"\r", b"\n"):
        try:
            jump()  # no window or no session to go to: the view simply stays
        except Exception:  # as in main(): an odd session file must not end the view; the next round shows the error
            pass
    if key == b"i" and session is not None:
        try:
            add_idea(board_of(session), input("Idee: "), clock())
        except (EOFError, KeyboardInterrupt, OSError):
            pass  # cancelled, or the board is not writable: the next refresh shows no new idea
    return key if key in (b"i", b"f") else b""


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
            # a session start also follows compaction, resume and clear, which may have lost what was told: tell it all again
            shown = [] if event == "SessionStart" else shown_file.read_text().split()
        except OSError:
            shown = []
        # shortcut: ideas with the same text and time count as one, because only a hash is kept; upgrade if that bites
        new = {}
        for e in parse_board(text, clock().astimezone().date())[IDEAS]:
            line = "Neue Idee von vino: " + e.text
            digest = hashlib.sha256(f"{e.ts}|{line}".encode()).hexdigest()
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
    if sys.argv[1:] == ["bar", "--focus"]:
        return bar_focus()
    if sys.argv[1:2] == ["bar"]:
        try:
            out = bar_json()
        except Exception as e:  # the bar polls: a broken round shows nothing, the next one retries
            print("lage:", e, file=sys.stderr)
            out = {"text": ""}
        print(json.dumps(out, ensure_ascii=False))
        return 0
    ap = argparse.ArgumentParser(prog="lage", description="Show what a Claude Code session is doing now.")
    ap.add_argument("--dir", help="follow the newest session started in this folder (default: the Cockpit master window)")
    ap.add_argument("--once", action="store_true", help="print one frame and exit")
    ap.add_argument("--full", action="store_true", help="start with the whole board (the key f switches)")
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
    session, full, seen = None, args.full, {}  # seen: sessionId -> the board entries shown when the full view closed
    try:
        while True:
            try:
                session, ended = pick(session)
                sid = session and session["sessionId"]
                lines = frame(session, ended, where, full, seen.get(sid, frozenset()))
            except Exception as e:  # the view runs for hours (it reads every live session): a bad round shows why, the next one tries again
                if args.once:
                    raise
                lines = [clean(f"lage: {e}", cols())]
            if args.once:
                print("\n".join(lines))
                return 0
            # home, then each line cleared to its end, then everything below: no flicker
            sys.stdout.write("\x1b[H" + "".join(x + "\x1b[K\n" for x in lines) + "\x1b[J")
            sys.stdout.flush()
            if wait(2, session) == b"f":
                full = not full
                if not full:
                    seen[sid] = board_entries(session)  # the owner has looked at the whole board: not new any more
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
