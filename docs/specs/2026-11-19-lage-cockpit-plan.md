# Cockpit window overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The lage overview shows only DU (the owner's next three steps) and one honest line per live session; LOG,
AUFGABEN and NEU leave it, the full board stays behind `f`, Enter jumps to the session that needs him.

**Architecture:** `tools/lage.py` gets one state helper (`states()`) that maps `session_state()` to the overview's
honest states, and three renderers (`du_lines`, `session_rows`, `foot_line`) that `frame()` stacks for the overview;
the full branch is untouched. `bar_focus()` is split so Enter reuses its window search.

**Tech Stack:** Python 3 stdlib (writePython3Bin, flake8 with only E501 ignored), bash tests with a fake HOME.

**Spec:** `docs/specs/2026-11-19-lage-cockpit-design.md`

## Global Constraints

- Overview order: head, DU, `─` rule, session rows, `─` rule, foot. At most `rows() - 1` lines, never wider than `cols()`.
- DU order fixed: `liefern · N warten` (yellow) when `~/.local/state/liefern/warten/*.eintrag` exist; each live
  session with `status: waiting` (yellow, `▲ <label> wartet auf dich: <waitingFor>`), longest-waiting first; open
  `!` lines under "Für dich" without "→" from the boards of live sessions (red), newest first. A board step is cut at
  the first `": "` or `". "`. At most 3 steps; the rest is counted (`+N weitere`), a `!` line is never dropped silently.
- Row states: `wartet` only for `status: waiting` (▲, yellow); `arbeitet` for jetzt states `tool`/`denkt` (●, teal,
  plus the step text); `helfer` (●, teal, `Helfer arbeiten (n)`); everything else `ruht` (○, dim, plus age).
  `jetzt()`, `bar_json()`, `wartet_lines()` keep their behaviour.
- Foot: ` f alles   i Idee   ⏎ zur Sitzung` (without a followed session only ` ⏎ zur Sitzung`), on the right
  `5 h N % · Woche N %` from `~/.cache/claude-hud/usage.json` (5 h only while it is a number).
- Colours: the theme's ANSI ones; separators `\x1b[90m` (kitty color8 = base02 #303034).
- Never read `~/.claude/sessions/*.key`; lage writes only ideas into a board.

## Decisions where the design did not fit the code

- Head stays as today (`LAGE  <cwd>` + time; shared with the full view, whose tests stay unchanged), plus the existing
  status line `kein Claude …` or `Sitzung beendet` under it.
- `+N weitere` without `· f`: `f` shows only the followed session's board, the hidden steps may be on another one.
- Enter uses the overview's honest states, not `bar_focus()`'s choice (that one counts `idle` as waiting); it reuses
  the window search split out of `bar_focus()` as `focus(sid)`.
- Orphans removed with LOG/AUFGABEN/NEU: `log_lines`, `Transcript.steps/step`, `VERBS`, `task_lines`, the task fetch
  (`TASKS_URL`, `TASK`, `tasks_*`, `fetch_tasks`, `refresh_tasks`, `start_tasks`), `neu_line`, imports `deque`, `threading`.
- Tests that checked `jetzt()` and the wait lines through the old overview's `▶` line switch to `--full` (same lines).

## Review Focus

1. Two live sessions in one lab folder share a board: its `!` line must count once (dedupe by board path).
2. A board step without `": "`/`". "` and longer than the pane: cut with `…`, never wrapped.
3. `usage.json` missing, not JSON, `seven_day` null, `five_hour` a number: foot without that part, never a crash.
4. Small panes (LINES 5..60, COLUMNS 45/90) with 6 live sessions and 5 open `!` lines: height and width hold, rows
   fold into `+N weitere Sitzungen`, DU keeps its `+N`.
5. A transcript that grows while lage runs: rows follow it (`session_state()` only tails once, `states()` must update).

---

### Task 1: The new overview

**Files:** Modify `tools/lage.py`, `tools/lage.test.sh`

**Interfaces:**
- Produces: `states() -> list[tuple[dict, str, datetime | None, str]]` (session, state in `wartet|arbeitet|helfer|ruht`,
  since, jetzt text without `  seit …`), live sessions only, by `startedAt`; `du_lines(live, width, most=3) -> list[str]`;
  `session_rows(live, width) -> list[str]`; `foot_line(width, keys) -> str`; `GREY`.

- [x] **Step 1: Write the failing tests** in `tools/lage.test.sh` (replace test_log, test_neu_line, test_tasks,
  test_tasks_offline, test_tasks_off; drop `LAGE_TASKS_URL`):
  - `test_overview_rows`: busy tool call → ` ● src-a  arbeitet  x`; `status idle` → ` ○ src-a  ruht  20 s` and no
    `wartet auf dich`; `status waiting 'Erlaubnis'` → ` ▲ src-a  wartet auf dich  Erlaubnis`; idle with a running
    helper → ` ● src-a  Helfer arbeiten (1)`; a dead session has no row; no live session → ` keine Sitzung`.
  - `test_du`: empty → ` DU  nichts offen`; 2 queue files → ` 1  liefern · 2 warten`; a waiting session → its step;
    board `- 14:05 ! Brief an die Behörde: Name fehlt`, `- 14:06 ! Mrija. Passwort`, `- 14:07 ! alt → erledigt`,
    `- 14:08 normal` → steps `Mrija` before `Brief an die Behörde`, nothing with `alt`/`normal`; 5 steps →
    3 shown + `    +2 weitere`; Review Focus 1 and 2.
  - `test_foot`: ` f alles   i Idee   ⏎ zur Sitzung` and right-aligned `Woche 38 %`; `five_hour` 12 → `5 h 12 % · Woche 38 %`;
    Review Focus 3; `--dir` on an empty folder → ` ⏎ zur Sitzung` without `f alles`.
  - Review Focus 5 as a python check through `lage.states()`.
  - `test_height`: Review Focus 4 for the overview; the `--full` half unchanged.
  - Switch to `--full`: the `tool` helper, test_tool_use, test_partial_line, test_other_tools, test_end_turn,
    test_helpers, test_thinking, test_status, test_age, test_control_chars, test_ended, test_no_transcript,
    test_master's `▶` check, test_wartet*, and test_incremental's highlight (`frame(..., True)`); test_none,
    test_master_none_lists_sessions, test_idea_key and test_f_key follow the new overview (f_key: NEU through
    the full view's `(1 neu)`).
- [x] **Step 2: Run** `bash tools/lage.test.sh` → FAIL at the first new assertion.
- [x] **Step 3: Implement** the Interfaces above and the overview branch of `frame()` (also for `session is None`);
  `session_state()` stays, `states()` calls `tr.update()` before it; remove the orphans listed above.
- [x] **Step 4: Run** `bash tools/lage.test.sh` → `ok`; `flake8 --ignore=E501 tools/lage.py` → clean.
- [x] **Step 5: Commit** `feat(lage): cockpit overview shows DU and one line per session`.

### Task 2: Enter jumps to the session that needs the owner

**Files:** Modify `tools/lage.py`, `tools/lage.test.sh`

**Interfaces:**
- Consumes: `states()`. Produces: `focus(sid: str) -> int` (0 focused, 1 no window), `jump() -> int`.

- [x] **Step 1: Write the failing test** `test_enter` after the `bar --focus` tests, with the same fake windows: in a
  pty, Enter (`\r`) with an idle window (14:00) and a busy one (14:05) dispatches `address:0xbusy` (bar --focus would
  take the idle one); with a waiting one added, `address:0xwait`; only idle windows → no dispatch, lage keeps running.
- [x] **Step 2: Run** → FAIL (no dispatch).
- [x] **Step 3: Implement**: split `bar_focus()` into the choice and `focus(sid)`; `jump()` picks the longest-waiting
  `wartet`, else the longest-working `arbeitet`/`helfer`; `wait()` ends on `\r`/`\n` and calls `jump()`.
- [x] **Step 4: Run** `bash tools/lage.test.sh` → `ok` (the `bar --focus` cases unchanged).
- [x] **Step 5: Commit** `feat(lage): Enter jumps to the session that waits, else the one that works`.

### Task 3: More rows for lage, check against the mock-up

**Files:** Modify `modules/user/desktop/hyprland/scripts.nix` (`--bias=35` → `--bias=25`), this plan's boxes

- [x] **Step 1:** Change the bias; `alejandra` on the file.
- [x] **Step 2:** `COLUMNS=56 LINES=26 python3 tools/lage.py --once` on the laptop: compare with the mock-up (DU on top,
  rules, one row per live session, foot with `Woche`).
- [x] **Step 3:** `nix build .#nixosConfigurations.bandit.config.home-manager.users.vino.home-files --no-link` (lage
  with its flake8 run; never the full flake check).
- [x] **Step 4: Commit** `feat(cockpit): lage gets three quarters of the pane`; queue the laptop switch with `liefern add`.
