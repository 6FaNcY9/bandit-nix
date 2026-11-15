# lage overview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the lage pane into a short overview (JETZT, WARTET, DEINE AUFGABEN, LOG, NEU) with the full board behind `f`, and drop the shell split from the Cockpit pane.

**Architecture:** Rework `tools/lage.py` in place: a new main `frame` with a row budget, the old board frame kept as the `f`/`--full` view, steps collected in `Transcript`, tasks fetched by a daemon thread into a cache file. `scripts.nix` launches `lage` directly in the cockpit kitty.

**Tech Stack:** Python 3 stdlib (flake8 in the build, E501 ignored), bash tests with fixture HOME, Nix/HM (Alejandra).

**Spec:** `docs/specs/2026-11-15-lage-overview-design.md` (builds on `docs/specs/2026-11-15-claude-lage-design.md`).

## Global Constraints

- Stdlib only; `writePython3Bin` runs flake8 with `E501` ignored (`scripts.nix:6`).
- Frame ≤ `LINES - 1` lines, every line ≤ `COLUMNS` characters; one line per entry in the main view (`clean(x, width)`), wrapping only in the full view.
- Task text is foreign data: only through `clean()`; never into `hook()` output or a board.
- `LAGE_TASKS_URL` overrides the URL `https://memory.tail7facc9.ts.net/notes/lagebild.md`; empty = tasks off. The test harness exports `LAGE_TASKS_URL=` so no test touches the network.
- `board_path`, `add_idea`, `hook` behaviour unchanged.
- UI words exactly: `JETZT ▶ `, `! WARTET  `, `DEINE AUFGABEN`, `LOG  (was Claude macht)`, `NEU  `, `i = Idee   f = alles zeigen`, `i = Idee   f = zurück`, `nicht erreichbar`, `(Stand HH:MM)`, `+N weitere`.

## Review Focus

1. Tailscale off / DNS hangs: keys `i` and `f` still react at once; the box shows the cache with `(Stand HH:MM)` or `nicht erreichbar`.
2. A lagebild with odd rows (no `(who)`, ESC bytes, 500-char text, other headings after the section): no crash, nothing past the section, control chars shown as `?`.
3. Tiny pane (LINES 8, COLUMNS 45): header, JETZT, WARTET, tasks heading and NEU stay; nothing wider than the pane.
4. A burst of 30 reads in a row: LOG shows one collapsed line, not 8 lines of `liest …`.
5. `f` opened and closed: entries seen in the full view are no longer counted as NEU.

---

### Task 1: Main view with JETZT, WARTET, LOG, NEU; old view behind `--full`

**Files:**
- Modify: `tools/lage.py` (`Transcript` 218-292, `jetzt` 309-337, `sitzungen_lines` 340-367, `board_lines` 464-499, `frame` 506-538, `main` 602-642)
- Test: `tools/lage.test.sh`

**Interfaces:**
- Produces: `frame(session, ended, where, full=False, seen=None) -> list[str]`; `Transcript.steps: deque[(datetime, str, int)]` (time, text, count), maxlen 8; `wartet_lines(followed_sid, cols) -> list[str]`; `neu_line(board, since) -> str`; `log_lines(tr, cols, n) -> list[str]`; CLI flag `--full`.
- Consumes: existing `tool_text`, `waiting_for`, `clean`, `parse_board`, `board_lines`.

- [ ] **Step 1: Update the tests first**
  - `JETZT` is one line: `JETZT ▶ <text> (seit 20 s)`; waiting: `JETZT ▶ wartet auf dich: <waitingFor> (seit …)`. Replace every `"<Tool> · seit …"` second-line assertion (6 places) accordingly.
  - Existing board tests (`test_neu`, `test_older`, `test_old_day`, `test_wrap`, `test_ideas`, `test_odd_board`, `test_board_unit`, master/tmux tests that grep board text) call `lage … --once --full`.
  - SITZUNGEN tests (`test_sitzungen`, `_answered`, `_names`, `test_dead_hidden`, `test_cap`, `test_none`, `test_master_none_lists_sessions`) become WARTET tests: only *other* waiting sessions, one line each `! WARTET  <name>: <why>`; 5 waiting → 2 lines + `+3 weitere`; none waiting → no WARTET line; the followed session never appears; names/control chars as before. `test_sitzungen_cache` keeps its byte-count assertion.
  - New `test_log`: tool_use entries Read a.py, Read b.py, Read c.py, Bash "baut System", Agent "Design prüfen" → main view lines, newest first: `14:12 Helfer: Design prüfen`, `… baut System`, `… liest c.py +2`; text entries and tool_results are no steps; an entry from yesterday shows `14.11.`.
  - `test_height` → `test_budget`: for LINES in 60 40 27 20 11 8 5 and COLUMNS 45 90: ≤ LINES-1 lines, `widest` ≤ COLUMNS, line 1 `LAGE …`, line 2 `JETZT ▶ …`; at LINES 27 the order is `JETZT`, `WARTET`, `LOG`, `NEU`, `i = Idee   f = alles zeigen`; at LINES 8 `NEU` is still there.
  - New `test_neu_line`: board with 2 new Funde (one `!`), 1 new Für dich, 3 open ideas → `NEU  2 Funde · 1 für dich · 3 Ideen` and the line starts with `! ` when a new entry is important.
  - `test_home_cut` stays (header still `LAGE  <short cwd>`).
- [ ] **Step 2: Run `tools/lage.test.sh`** — expect FAIL at the first changed assertion.
- [ ] **Step 3: Implement**
  - `Transcript.take`: for each `tool_use` item of a non-sidechain assistant entry append a step; collapse into the last step when the text is equal, or both texts start with the same verb from `("liest ", "sucht ", "ändert ")` → keep newest time and text, count + 1. `Helfer: ` steps never collapse.
  - `jetzt` returns one line (text plus ` (seit …)`); its state logic stays.
  - `wartet_lines` replaces `sitzungen_lines` (same session loop and transcript cache).
  - `board_lines(board, since, cols, space)`: `since` replaces `owner_ts`; extract the NEU test into `is_new(e, cut)` used by both `board_lines` and `neu_line`.
  - `frame`: `since = max(owner_ts, seen)` (either may be None). `full=True` → head, JETZT, WARTET, rule, board, rule, `i = Idee   f = zurück` (old budget code). Main view row budget (room = LINES-1): always head, JETZT, WARTET lines, NEU line; then add while they fit, in this order: LOG heading + 3 steps, LOG up to 8, the key line, 3 rules (before LOG, before NEU, after WARTET). Render order: head, JETZT, WARTET, rule, LOG, rule, NEU, key line. Red (`\x1b[1;31m`) on `! WARTET` lines and HIGHLIGHT on a `!` NEU line, terminal only. `session is None`: head, `kein Claude …`, WARTET.
- [ ] **Step 4: Run `tools/lage.test.sh`** — expect `ok`. Run `flake8 --ignore=E501 tools/lage.py` (via `nix shell nixpkgs#python3Packages.flake8`).
- [ ] **Step 5: Commit** `feat(lage): overview main view, full board behind --full`

### Task 2: DEINE AUFGABEN from lagebild

**Files:** Modify `tools/lage.py`; Test `tools/lage.test.sh`

**Interfaces:**
- Produces: `fetch_tasks(url) -> list[str] | None` (cleaned rows of `## Waiting for a human`, ≤ 10; None on any error); `start_tasks() -> threading.Thread | None` (None when the URL is empty); `task_lines(cols, n) -> list[str]` (heading + rows + `+N weitere`, from the cache file); cache `~/.local/state/lage/aufgaben.md`.
- Consumes: `frame` budget from Task 1 (tasks heading is fixed; up to 5 task rows go right after "LOG heading + 3 steps" in the allocation order; render after WARTET, before LOG, with its own rule).

- [ ] **Step 1: Tests** with `LAGE_TASKS_URL=file://$t/lagebild.md` and a fixture holding `## Waiting for a human` with 10 rows `N. proj (vino): Aufgabe N (vino) 2026-11-16`, one row `(albert)`, one row with ESC, then `## Projects` with a row that must not show:
  - `test_tasks`: heading `DEINE AUFGABEN  10+`; 5 rows ` □ proj: Aufgabe 1` …; `+N weitere`; no `albert` row; ESC shows `?`; nothing from `## Projects`; cache file written.
  - `test_tasks_offline`: URL to a missing file + cache with mtime 20 min old → `(Stand HH:MM)` in the heading, rows from cache; no cache → ` nicht erreichbar`.
  - `test_tasks_off`: `LAGE_TASKS_URL=` → no `DEINE AUFGABEN` line.
- [ ] **Step 2: Run tests** — FAIL.
- [ ] **Step 3: Implement** with `urllib.request.urlopen(url, timeout=3)`, `read(65536)`, decode with `errors="replace"`; parse rows with `^\d+\.\s+(\S+) \([^)]*\): (.*?)(?: \(([^)]*)\))?(?: \S+)?$`, keep who `vino` or missing; write the cache atomically (tmp + `os.replace`, as `add_idea`); the daemon thread loops fetch → sleep 300. `main` starts it; `--once` joins it for ≤ 3 s. Count `10+` when the source list had 10 rows.
- [ ] **Step 4: Run tests + flake8** — `ok`.
- [ ] **Step 5: Commit** `feat(lage): owner tasks from lagebild`

### Task 3: `f` toggle, Cockpit pane without the shell

**Files:** Modify `tools/lage.py` (`wait`, `main` loop), `modules/user/desktop/hyprland/scripts.nix:7-12,86-99`, `tools/hypr-cockpit.test.sh:63-66`

**Interfaces:** `wait(seconds, session) -> bytes` returns the key that ended the wait (`b"f"`, `b"i"` or `b""`); `f` returns at once.

- [ ] **Step 1: Tests**
  - `test_idea_key` gets a sibling `test_f_key` (pty, like it): `f` shows `FUNDE` and `i = Idee   f = zurück`; `f` again shows `i = Idee   f = alles zeigen`, and an entry new before the toggle no longer counts in `NEU`.
  - `hypr-cockpit.test.sh`: kitty log is `--class cockpit-log /nix/store/*-lage/bin/lage`; no session file.
- [ ] **Step 2: Run both test files** — FAIL.
- [ ] **Step 3: Implement** the toggle (`seen = clock()` when the full view closes); delete `cockpitSession`; launch `setsid -f "$kitty" --class cockpit-log ${lage}/bin/lage`; fix the comment at `scripts.nix:86-87`.
- [ ] **Step 4: Run** `tools/lage.test.sh`, `tools/hypr-cockpit.test.sh`, `nix fmt -- modules/user/desktop/hyprland/scripts.nix`, build `nix build .#nixosConfigurations.bandit.config.system.build.toplevel --no-link`.
- [ ] **Step 5: Commit** `feat(cockpit): lage-only pane with f toggle`
