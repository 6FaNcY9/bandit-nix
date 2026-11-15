# Lage (live view of what Claude is doing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `lage`, a terminal view in the Cockpit's right pane (and a `pt dash` pane) that shows what the Claude Code session in the master window does now, its board, and all running sessions, and lets the owner drop in ideas that a hook feeds to Claude once.

**Architecture:** One stdlib-only Python file `tools/lage.py` holds the view, the idea append, the window probe and the Claude Code hook (`lage hook`), so the board-path rule exists once. Nix packages it as `~/.local/bin/lage`; `hypr-cockpit` (bash) asks `lage --probe` whether the work window runs Claude. The sec repo only adds one tmux pane and one ignore line. `memory-save.sh` gets a skip for live engagements first.

**Tech Stack:** Python 3 stdlib (`pkgs.writers.writePython3Bin`, the pattern of `modules/user/desktop/keyring-unlock.nix`), bash + jq for `hypr-cockpit`, `memory-save.sh` and all tests. Python instead of bash for `lage` because it needs character-correct wrapping of German text, minute/day time maths and incremental reads of 60 MB transcripts; in bash + jq that is well past the spec's 150-line mark.

**Spec:** `docs/specs/2026-11-15-claude-lage-design.md` (read it first; this plan argues from it).

## Global Constraints

- Repos: bandit-nix worktree `/home/vino/src/bandit-nix-lage`, branch `feat/claude-lage`. sec changes in a new worktree `/home/vino/src/sec/.worktrees/lage-pane`, branch `feat/lage-pane` off `feat/sec-labs` (3f73c06).
- Only `modules/user/` is live in bandit-nix; never touch `nixos/` or `home/`.
- No deploy, no `nh os switch`, no push, no merge. The owner does those (bandit-nix merges must be signed).
- Never read `~/src/sec/live/*/`, `~/src/sec/loot/`, `*.key`, `secrets/`, `.env`. Never print transcript message text; tests use fixtures only.
- The pane never takes focus and never becomes master: window class stays `cockpit-log` (`rules.nix` is not changed).
- A board inside `~/src/sec/live/<name>/` never leaves that folder: no copy of board text in `~/.local/state`, git, or memory.
- Pane text: German labels exactly as in the spec (`LAGE`, `JETZT`, `FUNDE`, `UNGEPRÜFT`, `FÜR DICH`, `DEINE IDEEN`, `SITZUNGEN`, `NEU`, `wartet auf dich`, `Helfer arbeiten (N)`, `kein Claude im Hauptfenster`, `Sitzung beendet`, `+N ältere`, `i = Idee eintragen`). No sideways scroll: every line fits `COLUMNS`.
- Board headings exactly `## Funde`, `## Ungeprüft`, `## Für dich`, `## Deine Ideen`. Entry line: `- [YYYY-MM-DD ]HH:MM [! ]text`; ideas `- [ ] …` / `- [x] …`.
- Board path: start cwd inside `~/src/sec/{re,ctf,live}/<name>/` → `<that lab folder>/.claude/lage.md`; else `~/.local/state/lage/<sessionId>.md`.
- No colour codes when stdout is not a terminal (tests grep plain text).
- Nix: `nix fmt -- <changed files>`; never full `nix flake check` (earlyoom); always `--no-update-lock-file --max-jobs 1`. New files must be `git add`ed before any `nix build` (flakes see tracked files only).
- Commits: repo style (`feat(desktop): …`), each message ends with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.

Facts checked on real files 2026-11-15 (Claude Code 2.1.323), beyond the spec:

- `~/.claude/sessions/` also holds files without `sessionId` (keys `peerToken, pidDomain, procStart`): skip them. `status` seen: `busy`, `idle`, `shell`. `/proc/<pid>/comm` of a session is `claude`.
- Topic entry: `{"type":"ai-title","aiTitle":"…","sessionId":"…"}`, no timestamp.
- Owner prompt: `type == "user"` and `.origin.kind == "human"` (helper mail has `kind: "peer"`, notifications `task-notification`; both may lack `isMeta`).
- Helper state: `<sessionId>/subagents/agent-*.meta.json` has `finished: true` when done, no `finished` key while running.
- Hook stdin has `session_id`, `cwd` (current, not start), `hook_event_name`, and `agent_id` when the call comes from a helper. `PostToolUse` only passes text to Claude as JSON `hookSpecificOutput.additionalContext`; that form works for all three events.
- Transcripts reach 60 MB; most bytes are `api-request-blob` lines.
- `tmux` is not on the laptop's global PATH. `~/.local/bin` is.
- `tools/memory-save.sh` on this branch is byte-identical to the installed `~/.claude/hooks/memory-save.sh`.

## Review Focus

1. Terminal control characters in text taken from a transcript (a CTF box can steer a Bash description or Claude's last line): the pane prints them as `?`, never raw. Test in Task 2.
2. A half-written last transcript line or a non-JSON line: skipped, read again on the next refresh, no crash. Test in Task 2.
3. A board entry written in the same minute as the owner's last prompt (board has minutes, transcript has seconds): counts as NEU. Test in Task 3.
4. A hand-edited board (empty file, unknown heading, missing section, line without time, bare `HH:MM`): no crash; such entries show without NEU. Test in Task 3.
5. A folder that only starts like a lab or live folder (`~/src/sec/live-notes`, `~/src/sec/ctf-old/x`): not treated as live or lab. Tests in Task 1 and Task 3.

## File Structure

| File | Role |
|---|---|
| `tools/memory-save.sh`, `tools/memory-save.test.sh` (modify) | Skip live engagements |
| `tools/lage.py` (create) | The whole program: view, `--idea`, `--probe`, `hook` |
| `tools/lage.test.sh` (create) | Fixture tests: fake `HOME`, fake `hyprctl`/`tmux`, fake `claude` process |
| `modules/user/desktop/hyprland/scripts.nix` (modify) | Package `lage`; `hypr-cockpit` opens it |
| `tools/hypr-cockpit.test.sh` (create) | Runs the built `hypr-cockpit` against stubs |
| sec: `nix/lib/dash.sh`, `.gitignore`, `tests/pentest-functions-test.sh` (modify) | `lage` pane, ignore rule |
| `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/hooks/memory-save.sh` | Owner files, changed by the controller only (Tasks 1 and 8) |

CLI of `tools/lage.py` (the contract every task shares):

```
lage [--dir DIR] [--once]         view; --once prints one frame and exits
lage [--dir DIR] --idea TEXT      append an owner idea to the followed board, exit
lage --probe PID                  exit 0 if a Claude session runs under window pid PID, else 1
lage hook                         Claude Code hook; reads the hook JSON on stdin
```

Test seams, all through the environment: `HOME` (all paths come from `Path.home()`), `PATH` (fake `hyprctl`, `tmux`), `COLUMNS`/`LINES` (`shutil.get_terminal_size`), `TZ=UTC`, and `LAGE_NOW` (ISO time used as "now"; the only seam added for tests).

`tools/lage.test.sh` follows `tools/memory-save.test.sh`: `set -euo pipefail`, temp dir, bare `[[ … ]]` assertions, `echo ok` at the end. Shared helpers, written in Task 2 and reused later:

```bash
lage() { python3 "$here/lage.py" "$@"; }
session() { # session <pid> <sid> <name> <start cwd>: writes $HOME/.claude/sessions/<pid>.json and an empty transcript
entry()   { # entry <sid> <json>: appends one line to that session's transcript
```

A live pid for fixtures is `$$`; a dead one is `999999`.

---

### Task 1: memory-save skips live engagements (ship first)

**Files:**
- Modify: `tools/memory-save.sh` (after the `[ -r "$transcript" ] …` guard, line 38)
- Test: `tools/memory-save.test.sh`

- [ ] **Step 1: Write the failing tests** (append before `echo ok`; give `prompts` an optional third argument, the cwd, default `/x/proj`)

```bash
# Live engagements never reach the memory server, by start cwd or any later cwd.
live=$HOME/src/sec/live
prompts "$p/dddddddd-1.jsonl" 3 "$live/acme"; touch -d '2 hours ago' "$p/dddddddd-1.jsonl"
prompts "$p/eeeeeeee-1.jsonl" 3
echo '{"type":"user","cwd":"'"$live"'/acme/sub","message":{"content":"q"}}' >>"$p/eeeeeeee-1.jsonl"
touch -d '2 hours ago' "$p/eeeeeeee-1.jsonl"
prompts "$p/ffffffff-1.jsonl" 3 "$HOME/src/sec/live-notes"; touch -d '2 hours ago' "$p/ffffffff-1.jsonl"
before=$(wc -l <"$CALLS"); sweep
[[ $(wc -l <"$CALLS") -eq $((before + 1)) && $(tail -n 1 "$CALLS") == 2026-11-10-dev-live-notes-ffffffff ]]
echo "{\"transcript_path\":\"$p/dddddddd-1.jsonl\",\"session_id\":\"dddddddd-1\"}" | "$here/memory-save.sh" --fg
[[ $(wc -l <"$CALLS") -eq $((before + 1)) ]]                       # SessionEnd skips it too
[[ -e $HOME/.local/state/memory-saved/dddddddd-1 ]]                # marked, so the sweep does not rescan it
```

- [ ] **Step 2:** Run `tools/memory-save.test.sh`. Expected: fails at the first new assertion (two extra calls).
- [ ] **Step 3: Implement the skip.** In the `--fg` path, before `cwd=`: if any transcript line has `.cwd` equal to `$HOME/src/sec/live` or starting with `$HOME/src/sec/live/`, `touch "$saved/$sid"` and `exit 0`. One `jq` call; add one line to the header comment.
- [ ] **Step 4:** Run `tools/memory-save.test.sh`. Expected: `ok`.
- [ ] **Step 5: Commit** `fix(memory): memory-save skips live engagement sessions`.
- [ ] **Step 6 (controller, right after review, not the implementer):** `install -m 700 /home/vino/src/bandit-nix-lage/tools/memory-save.sh ~/.claude/hooks/memory-save.sh`, then `cmp` the two files. Expected: no output.

### Task 2: `lage` core: follow a session by folder, JETZT line

**Files:**
- Create: `tools/lage.py`, `tools/lage.test.sh`

**Interfaces (produced, used by Tasks 3 to 6):**
- `clean(s: str, limit: int) -> str`: first line only, control characters (`< 0x20`, `0x7f`–`0x9f`) become `?`, cut to `limit` with `…`.
- `sessions() -> list[dict]`: every `~/.claude/sessions/*.json` that has `sessionId`, plus key `alive` (`/proc/<pid>` exists).
- `class Transcript(session_id)`: file found by glob `~/.claude/projects/*/<session_id>.jsonl` (no name rule needed). `update()` reads only bytes added since the last call, complete lines only, and parses a line only if it contains `"type":"assistant"`, `"type":"user"` or `"type":"ai-title"`. Fields: `last` (newest `assistant`/`user` entry that has a `timestamp`), `owner_ts` (datetime of the newest owner prompt or `None`), `title` (newest `aiTitle`), `last_text` (first line of the newest assistant `text` item), `helpers()` (count of `subagents/agent-*.meta.json` without `finished: true` whose `.jsonl` changed in the last 30 minutes).
- `jetzt(tr: Transcript, now: datetime) -> tuple[list[str], str]`: the JETZT lines and a state, one of `tool`, `denkt`, `wartet`, `helfer`.
- `pick_by_dir(folder: str) -> tuple[dict | None, bool]`: newest (`startedAt`) alive session whose start `cwd` is the folder or inside it; if none is alive but a dead one matches, that one with `ended=True`.
- `frame(session: dict | None, ended: bool, where: str) -> list[str]`: the full pane as lines; `main()` prints it once (`--once`) or every 2 s after clearing the screen.

JETZT rules (from `tr.last`):

| Newest entry | Line 1 | Line 2 | State |
|---|---|---|---|
| assistant with a `tool_use` item (take the last) | Bash: `input.description`, else `Bash`. Read: `liest <basename>`. Edit/Write/MultiEdit/NotebookEdit: `ändert <basename>`. Grep/Glob: `sucht <pattern>`. Agent/Task: `Helfer: <description>`. Else the tool name | `<Tool> · seit <age>` | `tool` |
| assistant, `stop_reason` set and not `tool_use`, `helpers() == 0` | `wartet auf dich` (highlighted on a terminal) | `seit <age>` | `wartet` |
| same, `helpers() > 0` | `Helfer arbeiten (N)` | `seit <age>` | `helfer` |
| anything else (owner prompt, tool result, text before a tool call) | `denkt nach` | `seit <age>` | `denkt` |

Age: under 60 s `20 s`, under 60 min `3 min`, else `2 h`. Header: `LAGE  <start cwd with $HOME/src/ or $HOME/ cut off>` and right-aligned `Stand HH:MM`. No session: line `kein Claude in <folder>` (Task 6 adds the master wording). `ended`: JETZT shows `Sitzung beendet`. No transcript file: JETZT shows `Protokoll nicht gefunden`.

Not built (spec leaves both open): `wartet auf Erlaubnis`, and `Stand vor N min` (a frame is always fresh when drawn; the `seit` age carries the staleness).

- [ ] **Step 1: Write the failing tests** in `tools/lage.test.sh` (`export TZ=UTC COLUMNS=46 LINES=27 LAGE_NOW=2026-11-15T14:12:20Z`; `s1=aaaaaaaa-1`; fixture session `$s1` = pid `$$`, name `src-a`, start cwd `$HOME/w`)

```bash
# test_tool_use
entry $s1 '{"type":"assistant","timestamp":"2026-11-15T14:12:00Z","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"Bash","input":{"description":"prüft die Webseite"}}]}}'
entry $s1 '{"type":"mode"}'                                  # no timestamp: skipped
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"JETZT ▶ prüft die Webseite"* && $out == *"Bash · seit 20 s"* && $out == *"Stand 14:12"* ]]
# test_other_tools: Read /a/b/notes.md → "liest notes.md"; Agent description "Ports" → "Helfer: Ports"
# test_end_turn: assistant stop_reason end_turn → "wartet auf dich"
# test_helpers: plus subagents/agent-a1.meta.json '{}' and a fresh agent-a1.jsonl → "Helfer arbeiten (1)"; with {"finished":true} → "wartet auf dich"
# test_thinking: newest entry a user tool_result → "denkt nach"
# test_control_chars (Review Focus 1): description $'x\e[2Jy' → output has "x?[2Jy" and no ESC byte
# test_partial_line (Review Focus 2): append 'garbage' and '{"type":"assistant","timest' → same output as before, exit 0
# test_ended: only session in the folder has pid 999999 → "Sitzung beendet"
# test_none: lage --dir "$HOME/empty" --once → "kein Claude in"
# test_no_session_files: a sessions file {"peerToken":"x"} is ignored, no crash
```

- [ ] **Step 2:** Run `tools/lage.test.sh`. Expected: fails (`lage.py` missing).
- [ ] **Step 3: Implement** the interfaces above in `tools/lage.py`.
- [ ] **Step 4:** Run `tools/lage.test.sh`. Expected: `ok`.
- [ ] **Step 5: Commit** `feat(desktop): lage shows what a Claude session is doing now`.

### Task 3: Board: path, sections, NEU, older entries, ideas

**Files:**
- Modify: `tools/lage.py`, `tools/lage.test.sh`

**Interfaces:**
- Consumes: `Transcript.owner_ts`, `clean`, `frame`.
- Produces: `board_path(session_id: str, start_cwd: str) -> Path`; `parse_board(text: str, today: date) -> dict[str, list[Entry]]` with `Entry(ts: datetime | None, important: bool, done: bool | None, text: str)` (`done` is `None` outside Deine Ideen; bare `HH:MM` means today; unknown headings are dropped); `add_idea(path: Path, text: str, now: datetime) -> None`; `board_lines(board, owner_ts, cols, rows) -> list[str]`.

Rules the tests do not decide alone:
- NEU: `entry.ts` (minute) `>=` `owner_ts` cut to the minute, compared in local time. No `ts` or no `owner_ts`: not NEU.
- Section head: `FUNDE  3  (1 neu)`; `(… neu)` only when above 0; Deine Ideen shows `DEINE IDEEN  1 offen`. Empty or missing sections show `0`.
- Row: 4 columns `NEU ` or blanks, then `!` or `·`, two blanks, time (`14:02` today, `15.11.` older), text; ideas put `[ ]`/`[x]` before the text. Wrapped with `textwrap`, later lines indented to the text column. `!` rows highlighted on a terminal.
- Order: newest first; entries without time last; open ideas before done ones.
- Space: each section gets `max(2, (rows - 19) // 4)` screen lines; what does not fit becomes one line `+N ältere`.
- `add_idea` appends `- [ ] YYYY-MM-DD HH:MM <text>` as the last line of `## Deine Ideen`; creates the folder and a file with the four headings when missing; writes through a temp file and `os.replace`. Text goes through `clean(text, 200)`; empty text does nothing.
- Key `i` (only when stdin is a terminal): the 2 s wait is `select` on stdin in cbreak mode; `i` restores the terminal, asks `Idee: ` with `input()`, calls `add_idea`. Footer line `i = Idee eintragen`. No other keys.

- [ ] **Step 1: Write the failing tests**

```bash
# test_board_path
[[ $(lage --dir "$HOME/w" --idea 'A' && ls "$HOME/.local/state/lage/") == $s1.md ]]
session $$ bbbbbbbb-2 src-b "$HOME/src/sec/ctf/box1/sub"            # inside a lab folder
lage --dir "$HOME/src/sec/ctf/box1" --idea 'Cookie anschauen'
grep -qx -- '- \[ \] 2026-11-15 14:12 Cookie anschauen' "$HOME/src/sec/ctf/box1/.claude/lage.md"
# test_not_a_lab (Review Focus 5): start cwd $HOME/src/sec/ctf-old/x → board under ~/.local/state/lage/
# test_idea_keeps_file: add_idea on a board with all four sections filled leaves every other line unchanged (diff shows one added line)
# test_neu: owner prompt (origin.kind human) at 14:02:40Z; board Funde:
#   "- 2026-11-15 14:02 ! Admin-Login ohne Sperre"  (same minute, Review Focus 3)
#   "- 2026-11-15 13:50 Port 22 offen"
#   → output has "FUNDE  2  (1 neu)", a line matching "NEU !  14:02 Admin-Login", and "·  13:50 Port 22 offen" without NEU
# test_peer_is_not_owner: a later user entry with origin.kind "peer" does not move NEU
# test_older: 7 Funde entries, LINES=27 → exactly 2 entry rows in FUNDE and a line "+5 ältere"
# test_old_day: entry dated 2026-11-14 shows "14.11."
# test_wrap: a 120-character entry at COLUMNS=46 → no output line longer than 46 characters
# test_ideas: "- [ ] …" and "- [x] … → nichts drin" → "DEINE IDEEN  1 offen", open one listed first
# test_odd_board (Review Focus 4): empty file; file with only "## Notizen"; "- kein Zeitstempel"; "- 13:40 nur Uhrzeit" → exit 0, entries shown, none NEU except by rule
```

- [ ] **Step 2:** Run `tools/lage.test.sh`. Expected: fails at `test_board_path`.
- [ ] **Step 3: Implement** the interfaces and the `i` key; put the board block between two rules below JETZT in `frame`.
- [ ] **Step 4:** Run `tools/lage.test.sh`. Expected: `ok`.
- [ ] **Step 5: Commit** `feat(desktop): lage board with NEU marks and owner ideas`.

### Task 4: SITZUNGEN block

**Files:**
- Modify: `tools/lage.py`, `tools/lage.test.sh`

**Interfaces:**
- Consumes: `sessions()`, `Transcript`, `jetzt`, `clean`.
- Produces: `sitzungen_lines(followed_sid: str | None, cols: int) -> list[str]`, placed by `frame` under the board. Transcript objects are kept in a dict by session id across refreshes, so each file is read once and then only its new bytes.

Rules: one line per alive session, cut to `cols`, never wrapped: mark (`!` waits for the owner, else `▶` for the followed session, else blank), `name` (missing: first 6 characters of the session id), topic (`clean(title, 12)`), state (`arbeitet` for `tool`/`denkt`, `Helfer arbeiten`, `wartet: <clean(last_text)>`). Waiting sessions first, then by name. At most 6 lines, then `+N weitere`.

- [ ] **Step 1: Write the failing tests**

```bash
# test_sitzungen: $s1 (followed, tool_use), a second alive session "src-c8" with ai-title "Bot-Menü" and an end_turn whose text is "Soll ich es ausrollen?\nzweite Zeile"
out=$(lage --dir "$HOME/w" --once | sed -n '/^SITZUNGEN/,$p')
[[ $(sed -n 2p <<<"$out") == *"!"*"src-c8"*"Bot-Menü"*"wartet: Soll ich es ausrollen?"* ]]   # waiting first
[[ $(sed -n 3p <<<"$out") == *"▶"*"src-a"*"arbeitet"* && $out != *"zweite Zeile"* ]]
# test_dead_hidden: a session with pid 999999 has no line
# test_cap: 8 alive sessions → 6 lines and "+2 weitere"; no line longer than 46 characters
```

- [ ] **Step 2:** Run `tools/lage.test.sh`. Expected: fails at `test_sitzungen`.
- [ ] **Step 3: Implement** `sitzungen_lines`.
- [ ] **Step 4:** Run `tools/lage.test.sh`. Expected: `ok`.
- [ ] **Step 5: Commit** `feat(desktop): lage lists all running Claude sessions`.

### Task 5: `lage hook`: board path and owner ideas, each once

**Files:**
- Modify: `tools/lage.py`, `tools/lage.test.sh`

**Interfaces:**
- Consumes: `board_path`, `parse_board`, `sessions()`.
- Produces: subcommand `lage hook`. Reads the hook JSON on stdin; always exits 0.

Behaviour:
1. `agent_id` present, or `session_id` not matching `^[0-9a-f-]{8,}$`: no output.
2. Start cwd: `.cwd` of the sessions file with this `sessionId`; if none, the hook's `cwd`.
3. Lines: on `SessionStart` first `Lage-Board: <path>`. Then for each open idea not yet shown to this session `Neue Idee von vino: <text>`.
4. Shown state: `~/.local/state/lage/<sessionId>.shown`, one sha256 hex per shown idea line (hashes, so no lab text leaves the lab folder).
5. Any lines: print `{"hookSpecificOutput":{"hookEventName":"<event>","additionalContext":"<lines joined by \n>"}}`. No lines: print nothing. The hook never creates the board.

- [ ] **Step 1: Write the failing tests**

```bash
hook() { # hook <event> <session id> [agent id]
  jq -nc --arg e "$1" --arg s "$2" --arg c "$HOME/w" --arg a "${3:-}" \
    '{hook_event_name: $e, session_id: $s, cwd: $c} + (if $a == "" then {} else {agent_id: $a} end)' | lage hook; }
# test_start_tells_path
[[ $(hook SessionStart aaaaaaaa-1 | jq -r .hookSpecificOutput.additionalContext) == "Lage-Board: $HOME/.local/state/lage/aaaaaaaa-1.md" ]]
# test_idea_once
lage --dir "$HOME/w" --idea 'Cookie "anschauen" \ ü'
out=$(hook PostToolUse aaaaaaaa-1)
[[ $(jq -r .hookSpecificOutput.hookEventName <<<"$out") == PostToolUse ]]
[[ $(jq -r .hookSpecificOutput.additionalContext <<<"$out") == 'Neue Idee von vino: Cookie "anschauen" \ ü' ]]
[[ -z $(hook PostToolUse aaaaaaaa-1) && -z $(hook UserPromptSubmit aaaaaaaa-1) ]]
! grep -rq Cookie "$HOME/.local/state/lage/aaaaaaaa-1.shown"
# test_done_idea_not_shown: a "- [x]" idea never appears
# test_helper_skipped: `hook PostToolUse aaaaaaaa-1 a1` with a new open idea → no output; the next main call still shows it
# test_no_board: session cccccccc-3 without a board, PostToolUse → no output, exit 0, no file created
# test_bad_id: session_id "../x" → no output, exit 0
```

- [ ] **Step 2:** Run `tools/lage.test.sh`. Expected: fails at `test_start_tells_path`.
- [ ] **Step 3: Implement** `lage hook`.
- [ ] **Step 4:** Run `tools/lage.test.sh`. Expected: `ok`.
- [ ] **Step 5: Commit** `feat(desktop): lage hook tells Claude its board and new owner ideas`.

### Task 6: Follow the Cockpit master window; `--probe`

**Files:**
- Modify: `tools/lage.py`, `tools/lage.test.sh`

**Interfaces:**
- Consumes: `sessions()`, `frame`.
- Produces: `claude_session_under(pid: int) -> dict | None`; `master_pid() -> int | None`; `lage --probe PID`; the default mode (no `--dir`) of `main()`.

Rules:
- `master_pid()`: `hyprctl clients -j`. Own window = the client whose `pid` is one of this process's ancestors; its `workspace.id` is the workspace. Master = among that workspace's clients that are not floating, not `hidden`, not class `cockpit-log`: the one with the smallest `at[0]`, then `at[1]` (master layout has `orientation = "left"`, `settings.nix:76`; a hidden tab of a group drops out, so a tab switch is followed). No `hyprctl`, no own window, no candidate: `None`.
- `claude_session_under(pid)`: parent map from `/proc/[0-9]*/stat`; the first descendant with comm `claude` that has a sessions file wins. None, but a descendant whose comm starts with `tmux`: run `tmux list-clients -F '#{client_pid} #{pane_pid}'` (binary: `shutil.which("tmux")`, else that client's `/proc/<pid>/exe`), take the `pane_pid` of that client and search from it, itself included.
- Default mode: each refresh resolves again. Nothing found: `kein Claude im Hauptfenster`. Nothing found but the previous refresh had a session: keep its board and show `Sitzung beendet` until another session is found.
- `--probe PID`: exit 0 when `claude_session_under(PID)` finds one, else 1. No output.

Test fixtures: a fake `claude` is a script `$t/bin/claude` with shebang `#!/bin/sh` and body `sleep 60` (its `/proc/<pid>/comm` is then `claude`; checked). Start it in the background from a wrapper shell that stands in for kitty, write its sessions file with the fake's pid, kill it in the `trap`. Fake `hyprctl` prints `$CLIENTS`; fake `tmux` prints `$TMUX_CLIENTS`.

- [ ] **Step 1: Write the failing tests**

```bash
# test_probe: lage --probe <wrapper pid> exits 0; lage --probe <pid of a plain `sleep 60`> exits 1
# test_master: CLIENTS = [own window {pid: $$, class "cockpit-log", workspace 3, at [1700,0]},
#                         {pid: <wrapper>, workspace 3, at [0,0], hidden false},
#                         {pid: 1, workspace 3, at [0,0], hidden true}, {pid: 1, workspace 4, at [0,0]}]
#   → lage --once shows the header of the wrapper's session and its JETZT line
# test_master_none: master client pid without claude → "kein Claude im Hauptfenster"
# test_no_hyprctl: PATH without hyprctl → "kein Claude im Hauptfenster", exit 0
# test_tmux: wrapper runs a fake client named tmux; the fake claude runs outside the wrapper; TMUX_CLIENTS="<client pid> <claude pid>" → --probe exits 0
```

- [ ] **Step 2:** Run `tools/lage.test.sh`. Expected: fails at `test_probe`.
- [ ] **Step 3: Implement** the two functions, `--probe` and the default mode.
- [ ] **Step 4:** Run `tools/lage.test.sh`. Expected: `ok`.
- [ ] **Step 5: Commit** `feat(desktop): lage follows the Cockpit master window`.

### Task 7: Nix: install `lage`, Cockpit opens it

**Files:**
- Modify: `modules/user/desktop/hyprland/scripts.nix` (`let` block and `hypr-cockpit`, lines 37-85)
- Create: `tools/hypr-cockpit.test.sh`

**Interfaces:**
- Consumes: `lage --probe PID`, `lage` (default mode).
- Produces: `~/.local/bin/lage` on PATH (used by Task 8's settings entry and by `pt dash`).

Changes in `scripts.nix`:
- `let lage = pkgs.writers.writePython3Bin "lage" {flakeIgnore = ["E501"];} (builtins.readFile ../../../../tools/lage.py);` and `".local/bin/lage".source = "${lage}/bin/lage";`. The build runs flake8 over `lage.py`: fix what it reports in `lage.py`, do not widen `flakeIgnore`.
- `hypr-cockpit`: `kitty=''${HYPR_COCKPIT_KITTY:-${pkgs.kitty}/bin/kitty}` (test hook, one line). After the work window is made master: read its `pid` from `$clients`. If `${lage}/bin/lage --probe "$pid"` succeeds and `$logs` is 0: `setsid -f "$kitty" --class cockpit-log ${lage}/bin/lage`, whatever `$slots` is. Otherwise the existing `journalctl -f` branch, unchanged. Toggle-off is unchanged. Mind `set -e`: use `if`, not `&&` chains.

`tools/hypr-cockpit.test.sh <built script>`: fake `hyprctl` (`activeworkspace -j` → `{"id":1,"windows":2,"hasfullscreen":false,"tiledLayout":"dwindle"}`, `clients -j` → `$CLIENTS`, everything else logged), `HYPR_COCKPIT_KITTY` = a stub that writes its arguments to `$KITTY_LOG`, fake `HOME` and `XDG_RUNTIME_DIR`, the fake `claude` of Task 6. After each run wait up to 2 s for the detached stub, and remove the state file.

- [ ] **Step 1: Write the failing tests**

```bash
# test_plain_one_window: one tiled non-Claude window → KITTY_LOG is exactly "--class cockpit-log journalctl -f"
# test_plain_two_windows: two tiled non-Claude windows → KITTY_LOG stays empty
# test_claude_two_windows: work window (focusHistoryID 0) pid = wrapper with claude, plus a second window
#   → KITTY_LOG matches "--class cockpit-log /nix/store/*/bin/lage"
# test_claude_pane_exists: same plus a cockpit-log client on the workspace → KITTY_LOG stays empty
```

- [ ] **Step 2:** `git add tools/ modules/`, then

```bash
HF='.#nixosConfigurations.bandit.config.home-manager.users.vino.home.file'
tools/hypr-cockpit.test.sh "$(nix build "$HF.\".local/bin/hypr-cockpit\".source" --no-link --print-out-paths --no-update-lock-file --max-jobs 1)"
```

Expected: fails at `test_claude_two_windows` (old script opens nothing).
- [ ] **Step 3: Implement** the `scripts.nix` changes; `nix fmt -- modules/user/desktop/hyprland/scripts.nix`.
- [ ] **Step 4:** Run the Step 2 command again. Expected: `ok`. Then `"$(nix build "$HF.\".local/bin/lage\".source" --no-link --print-out-paths --no-update-lock-file --max-jobs 1)" --dir /tmp --once` prints a frame with `kein Claude in`.
- [ ] **Step 5: Config and system build**

```bash
HM='.#nixosConfigurations.bandit.config.home-manager.users.vino.xdg.configFile'
Hyprland --verify-config -c "$(nix build "$HM.\"hypr/hyprland.lua\".source" --no-link --print-out-paths --no-update-lock-file)"
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --no-link --no-update-lock-file --max-jobs 1
```

Expected: no config errors; build succeeds. Also `tools/lage.test.sh` and `tools/memory-save.test.sh` print `ok`.
- [ ] **Step 6: Commit** `feat(desktop): Cockpit opens lage when the work window runs Claude`.

### Task 8: sec repo: `lage` pane in `pt dash`, ignore rule

**Files (worktree `/home/vino/src/sec/.worktrees/lage-pane`):**
- Modify: `nix/lib/dash.sh` (`_pt_cmd_dash`, after the `for kind in notes hosts status` loop), `.gitignore` (lab block), `tests/pentest-functions-test.sh`

**Interfaces:**
- Consumes: `lage --dir DIR` from PATH.

- [ ] **Step 0:** `git -C /home/vino/src/sec worktree add .worktrees/lage-pane -b feat/lage-pane feat/sec-labs`. Run `bash tests/pentest-functions-test.sh` there. Expected: 73 passed.
- [ ] **Step 1: Write the failing tests** (three `test_case` entries next to the other dash cases; each case writes its own `tmux` stub into `$stub_bin` that logs its arguments to `$command_log`, exits 1 for `has-session` and 0 otherwise)

```bash
dash_adds_lage_pane_when_lage_is_installed()   # stub "lage" in $stub_bin, cd into a temp folder, _pt_cmd_dash
  # → $command_log has one split-window line containing "lage --dir" and that folder's path
dash_has_no_lage_pane_without_lage()           # no lage stub → $command_log has no "lage"
gitignore_covers_lage_board()                  # git -C "$repo_root" check-ignore -q live/.claude/lage.md ctf/x/.claude/lage.md re/x/.claude/lage.md
```

- [ ] **Step 2:** Run `bash tests/pentest-functions-test.sh`. Expected: the first and third new case fail (`live/.claude/lage.md` is re-included today; the per-lab paths are already ignored by `/live/*`, `/ctf/*`, `/re/*`).
- [ ] **Step 3: Implement.** `dash.sh`: when `command -v lage` succeeds, one more `tmux -S "$socket" split-window -t "$session:main" -d -c "$PWD"` running `lage --dir <$PWD quoted with printf %q>`, started directly (not through `_pt_dash_pane_loop`; `lage` redraws itself and reads the `i` key). Add `lage` to the `Panes:` info line in that case. `.gitignore`: add `.claude/lage.md` after the `/re/` lines with a one-line comment.
- [ ] **Step 4:** Run `bash tests/pentest-functions-test.sh`. Expected: 76 passed, 0 failed.
- [ ] **Step 5: Commit** in the sec worktree: `feat(sec): lage pane in pt dash, ignore lage boards`.

### Task 9: Owner files in `~/.claude` (controller only, after Tasks 1 to 8 are reviewed)

**Files:**
- Modify: `~/.claude/CLAUDE.md` (new section before `## Final report`), `~/.claude/settings.json`

These change every session that starts afterwards. The settings entry is safe before the deploy: it does nothing until `lage` is on PATH.

- [ ] **Step 1:** Back up both: `cp ~/.claude/settings.json ~/.claude/settings.json.bak-lage; cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak-lage`.
- [ ] **Step 2: Add this section to `~/.claude/CLAUDE.md`, exactly:**

```markdown
## Lage board

- The session-start hook prints `Lage-Board: <path>`. That file is this session's board; the owner watches it live. No such line: skip this section.
- During work that finds things (security, debugging, investigations) add one short line in simple German per item, as `- YYYY-MM-DD HH:MM text`: under `## Funde` each finding (start the text with `!` when it is important), under `## Ungeprüft` everything skipped, assumed or only guessed, under `## Für dich` everything the owner should check. If the file is missing, create it with these three headings and `## Deine Ideen`.
- Owner ideas arrive as `Neue Idee von vino: …`. Work them, then change their line under `## Deine Ideen` from `- [ ]` to `- [x]` and append ` → <short result>`.
- Never put secrets (passwords, hashes, keys) on the board in full; name them (`SSH-Schlüssel gefunden → loot/`). Helpers never write the board.
```

- [ ] **Step 3: Add the hook to `~/.claude/settings.json`:**

```bash
h='{"hooks":[{"type":"command","command":"command -v lage >/dev/null 2>&1 && lage hook || true"}]}'
jq --argjson h "$h" '.hooks.SessionStart += [$h] | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [$h]) | .hooks.PostToolUse += [$h]' \
  ~/.claude/settings.json.bak-lage > ~/.claude/settings.json
```

- [ ] **Step 4: Check:** `jq '[.hooks.SessionStart, .hooks.UserPromptSubmit, .hooks.PostToolUse] | map(map(select(.hooks[0].command | test("lage hook"))) | length)' ~/.claude/settings.json` prints `[1,1,1]`, and `jq '.hooks | keys | length' ~/.claude/settings.json` is the old count plus 1. `cmp tools/memory-save.sh ~/.claude/hooks/memory-save.sh` is silent (Task 1 Step 6 done).

### Task 10: Owner handover

- [ ] **Step 1:** Tell the owner, in short German, exactly this:
  - Deploy, on the laptop `bandit`, any time: `nh os switch ~/src/bandit-nix-lage` (or after the owner's own signed merge of `feat/claude-lage` into `main`, from the main checkout). The sec branch `feat/lage-pane` is merged by the owner together with `feat/sec-labs`.
  - Sessions that are already running do not load the new hook; start a new session for the checks.
  - Live checks from the spec: (1) Super+C with Claude in the master window opens the pane on the right, and it follows a tab switch in the master group; (2) `wartet auf dich` appears when Claude ends its turn; (3) press `i` in the pane, type an idea: it shows up in Claude's next step and gets ticked; (4) one practice CTF run with `pt ctf <name>` and `pt dash`: the `lage` pane shows that lab's board.
  - Two things only a live run can show: a helper call does not swallow an idea (the hook relies on `agent_id`), and Super+C in a workspace without Claude still opens the log pane as before.
  - `memory-save.sh` is the same file on every device: copy the new one to the phone too.
- [ ] **Step 2:** Update the project note in shared memory with branch names, commits and the open live checks.
