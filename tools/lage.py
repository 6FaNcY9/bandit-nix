"""lage: a terminal view of what a Claude Code session is doing right now.

lage [--once] [--full]   follow the Claude session in the Cockpit master window (Hyprland); with --dir DIR the newest one
  started in DIR. The main view is a short overview; --full (or the key f) shows the whole board.
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
import threading
import time
import tty
from collections import deque
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import NamedTuple

MARKERS = (b'"type":"assistant"', b'"type":"user"')
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
VERBS = ("liest ", "sucht ", "ändert ")  # LOG steps with one of these in a row join into one line
HIGHLIGHT, RED, RESET = "\x1b[1;7m", "\x1b[1;31m", "\x1b[0m"
TEAL, YELLOW, PURPLE, DIM = "\x1b[1;36m", "\x1b[1;33m", "\x1b[35m", "\x1b[2m"  # the theme's own ANSI colours
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
TASKS_URL = "https://memory.tail7facc9.ts.net/notes/lagebild.md"  # LAGE_TASKS_URL overrides it; empty turns tasks off
# N. project (store): text (who) [date]; text may hold ": " and is cut with … by lagebild already
TASK = re.compile(r"\d+\.\s+(\S+) \([^)]*\): (.*?)(?: \(([^)]*)\))?(?: \d{4}-\d\d-\d\d)?")
tasks_ok = None  # clock() of the last fetch of the tasks that worked, in this process


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
        self.steps = deque(maxlen=8)  # LOG: (time, text, count), oldest first

    def step(self, ts, text):
        """Add a LOG step; after a step with the same text or the same verb (VERBS) it joins that one. Helpers never join."""
        if self.steps and not text.startswith("Helfer: "):
            _, last, count = self.steps[-1]
            verb = next((v for v in VERBS if text.startswith(v)), None)
            if last == text or (verb and last.startswith(verb)):
                self.steps[-1] = (ts, text, count + 1)
                return
        self.steps.append((ts, text, 1))

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
            elif item.get("type") == "tool_use":
                tool_input = item.get("input")
                self.step(ts, tool_text(str(item.get("name") or "Tool"), tool_input if isinstance(tool_input, dict) else {}))
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


def wartet_lines(followed_sid, cols):
    """A line per other session that waits for the owner, by name: name and what it waits for. More than 3: the first 2
    and a +N weitere line."""
    now, rows = clock(), []
    for s in sessions():
        sid = s["sessionId"]
        if not s["alive"] or sid == followed_sid:
            continue
        tr = transcripts.setdefault(sid, Transcript(sid))
        tr.update()
        if jetzt(tr, now, s)[1] != "wartet":
            continue
        name = s.get("name")
        name = (clean(name, 12) if isinstance(name, str) else "") or clean(sid[:6], 6)
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


def neu_line(board, since, seen=frozenset()):
    """NEU  <new> Funde · <new> für dich · <open> Ideen, with ! in front when a new one is important."""
    cut = cut_of(since)
    new = {h: [e for e in board[h] if is_new(e, cut, seen)] for h in ("Funde", "Für dich")}
    bang = "! " if any(e.important for x in new.values() for e in x) else ""
    ideas = sum(e.done is False for e in board[IDEAS])
    funde = len(new["Funde"])
    return f"{bang}NEU  {funde} Fund{'' if funde == 1 else 'e'} · {len(new['Für dich'])} für dich · {ideas} Idee{'' if ideas == 1 else 'n'}"


def log_lines(tr, cols, n):
    """The newest n LOG steps, newest first: HH:MM (DD.MM. on another day), the text, +N for steps joined into it."""
    today, lit = clock().astimezone().date(), sys.stdout.isatty()
    out = []
    for ts, text, count in list(reversed(tr.steps))[:n]:
        t = ts.astimezone()
        when = f"{t:%H:%M}" if t.date() == today else f"{t:%d.%m.}"
        line = clean(f"{when} {text}" + (f" +{count - 1}" if count > 1 else ""), cols - 1)
        out.append(" " + (DIM + when + RESET + line[len(when):] if lit else line))
    return out


def tasks_url():
    return os.environ.get("LAGE_TASKS_URL", TASKS_URL)


def tasks_cache():
    return Path.home() / ".local/state/lage/aufgaben.md"


def fetch_tasks(url):
    """The rows under '## Waiting for a human' in lagebild, at most 10, cleaned; None when that cannot be read."""
    import urllib.request  # late: only the view needs it
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            text = r.read(65536).decode("utf-8", errors="replace")
    except Exception:  # any network or protocol error: keep the cache
        return None
    rows, inside = None, False
    for line in text.splitlines():
        name = heading(line)
        if name is not None:
            if inside:
                break
            inside = name == "Waiting for a human"
            rows = [] if inside else rows
        elif inside and line.strip():
            rows.append(clean(line, 300))
    return None if rows is None else rows[:10]


def refresh_tasks(url):
    """Fetch the tasks and replace the cache (atomic, as add_idea) when that worked."""
    global tasks_ok
    rows = fetch_tasks(url)
    if rows is None:
        return
    path = tasks_cache()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_text("".join(r + "\n" for r in rows), encoding="utf-8")
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)
    tasks_ok = clock()


def start_tasks():
    """A daemon thread that refreshes the tasks now and every 5 minutes, so a hanging network never stops the keys.
    Returns an event set after the first try, or None when tasks are off."""
    url, first = tasks_url(), threading.Event()
    if not url:
        return None

    def loop():
        while True:
            try:
                refresh_tasks(url)
            except OSError:
                pass  # the cache cannot be written: the box keeps what it has
            first.set()
            time.sleep(300)

    threading.Thread(target=loop, daemon=True).start()
    return first


def task_lines(cols, n):
    """AUFGABEN from the cache: the owner's rows (who vino or none), project and text in two columns, at most n lines
    below the heading; when they do not all fit, the last of them is +N weitere."""
    lit = sys.stdout.isatty()
    path = tasks_cache()
    try:
        cached = path.read_text(encoding="utf-8", errors="replace").splitlines()
        mtime = datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)
    except OSError:
        return [paint(TEAL, "AUFGABEN", lit), " " + paint(DIM, "nicht erreichbar", lit)][:1 + max(n, 0)]
    mine = [(m[1], m[2]) for m in map(TASK.fullmatch, cached) if m and m[3] in (None, "vino")]
    now = clock()
    stale = (tasks_ok is None or (now - tasks_ok).total_seconds() > 900) and (now - mtime).total_seconds() > 900
    count = clean(f"{len(mine)}" + (f"  (Stand {mtime.astimezone():%H:%M})" if stale else ""), max(cols - 10, 1))
    head = [paint(TEAL, "AUFGABEN", lit) + "  " + paint(DIM, count, lit)]
    if n <= 0:
        return head
    shown = mine if len(mine) <= n else mine[:n - 1]
    w = min(max((len(p) for p, _ in shown), default=0), 14)
    rows = []
    for project, text in shown:
        line = clean(f"{project[:w]:<{w}}  {text}", cols - 1)
        rows.append(" " + (paint(PURPLE, line[:w], lit) + line[w:] if lit else line))
    more = [" " + paint(DIM, f"+{len(mine) - len(shown)} weitere", lit)] if len(shown) < len(mine) else []
    return head + rows + more


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


def frame(session, ended, where, full=False, seen=frozenset()):
    """The whole pane as lines, at most one fewer than the pane is high (the newline after the last would scroll it).
    where finishes the sentence "kein Claude ", e.g. "in w". full: the whole board instead of the overview. seen: the
    entries the owner saw when last closing the full view of this session; they are no longer NEU."""
    n, width, room = clock(), cols(), max(rows() - 1, 1)
    lit = sys.stdout.isatty()
    stand = n.astimezone().strftime("%H:%M")
    left = "LAGE" if session is None else "LAGE  " + short(str(session.get("cwd")))
    left = clean(left, width - len(stand) - 1)
    head = [paint(TEAL, "LAGE", lit) + left[4:] + " " * (width - len(left) - len(stand)) + paint(DIM, stand, lit)]
    rule = "─" * width
    wartet = [paint(RED if x.startswith("!") else DIM, x, lit) for x in wartet_lines(session and session["sessionId"], width)]
    if session is None:
        top = head + [clean("kein Claude " + where, width)] + wartet
        box = task_lines(width, min(4, room - len(top) - 2)) if tasks_url() else []
        return (top + ([""] + box if box else []))[:room]
    state, since, tr = "", None, None
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
    if full:
        top = head + [line] + wartet
        foot = [rule, "i = Idee   f = zurück"]
        free = room - len(top) - 1 - len(foot)
        # lines per section: what is left, less the 4 headings and the 4 +N ältere lines; a pane too small for it loses
        # the end of the board first, then the end of the foot
        body = board_lines(board, since, width, max(1, (free - 8) // 4), seen)
        return (top + [rule] + body[:max(free, 0)] + foot)[:room]
    # Overview: header, the ▶ line, the waiting lines, the tasks heading and NEU always; then, while they fit, the LOG
    # with 3 steps, up to 4 task lines, a 4th step, the key line, and last the blank lines between the parts. A pane
    # too small even for the fixed lines loses its end.
    steps = log_lines(tr, width, 4) if tr else []
    neu = clean(neu_line(board, since, seen), width)
    if lit:
        bang = neu.startswith("! ")
        neu = (paint(RED, "! ", True) if bang else "") + paint(YELLOW, "NEU", True) + neu[2 + 3 if bang else 3:]
    on = bool(tasks_url())
    used, shown = 3 + len(wartet) + on, 0
    if steps and used + 1 + min(3, len(steps)) <= room:
        shown = min(3, len(steps))
        used += 1 + shown
    box = task_lines(width, min(4, room - used)) if on else []
    used += max(len(box) - 1, 0)
    if shown:
        more = min(len(steps) - shown, room - used)
        shown, used = shown + more, used + more
    keys = [paint(DIM, "i = Idee   f = alles", lit)] if used < room else []
    log = [paint(TEAL, "LOG", lit)] + steps[:shown] if shown else []
    parts = [p for p in (head, [line] + wartet, box, log, [neu] + keys) if p]
    gap = [""] if used + len(keys) + len(parts) - 1 <= room else []
    out = parts[0]
    for p in parts[1:]:
        out = out + gap + p
    return out[:room]


def wait(seconds, session):
    """Sleep. On a terminal, the key i asks for an idea and adds it to the board, f ends the wait at once; other keys do
    nothing. Returns the key that ended the wait, b"i" or b"f", else b""."""
    if not sys.stdin.isatty():
        time.sleep(seconds)
        return b""
    fd, saved = sys.stdin.fileno(), termios.tcgetattr(sys.stdin.fileno())
    key, end = b"", time.monotonic() + seconds
    try:
        tty.setcbreak(fd, termios.TCSANOW)
        while key not in (b"i", b"f") and (left := end - time.monotonic()) > 0:
            if select.select([fd], [], [], left)[0]:
                key = os.read(fd, 1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
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
    first = start_tasks()
    if args.once and first:
        first.wait(3)  # one frame: show fresh tasks if they come quickly, else the cache
    session, full, seen = None, args.full, {}  # seen: sessionId -> the board entries shown when the full view closed
    try:
        while True:
            session, ended = pick(session)
            sid = session and session["sessionId"]
            lines = frame(session, ended, where, full, seen.get(sid, frozenset()))
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
