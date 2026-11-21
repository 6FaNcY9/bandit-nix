# lage work view Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sessions report steps with `lage schritt`; the Cockpit shows them in a work view (key `a`), the bottom bar
shows the newest one, and the owner can answer a step with Stopp, Frage or Idee.

**Architecture:** Everything lives in the single stdlib script `tools/lage.py` (its established pattern), tested by
`tools/lage.test.sh` (bash, fake HOME, fixed clock `LAGE_NOW`). An append-only JSONL file next to each session's
board carries the steps; the view and the bar only read it. Waybar gets one module in `modules/user/desktop/waybar.nix`.

**Tech Stack:** Python 3 stdlib, bash + jq tests, Nix/Home Manager (Waybar), Hyprland (`hyprctl`).

**Spec:** `docs/specs/2026-11-21-lage-arbeit-design.md` (read it first; this plan does not repeat its rules).

## Global Constraints

- Stdlib only. `tools/lage.py` is built with `writePython3Bin` + flake8, only E501 ignored: after each task
  `nix shell nixpkgs#python3Packages.flake8 -c flake8 --show-source --ignore E501 tools/lage.py` prints nothing.
- `bash tools/lage.test.sh` ends with `ok` after each task (about 35 s). New tests go before the final `echo ok`, each
  under a `# test_<name>: <what>` comment like the existing ones; reuse `fresh`, `session`, `live`, `board`, `bfile`.
- The tests must never touch the real desktop: add `export XDG_RUNTIME_DIR=$t/run` (and `mkdir -p` it) to the
  test's top block in Task 1; calls that may run `hyprctl` use the `$t/fbin` stub (see `focus()` in the test file).
- UI text German and short; code, comments and commit messages English. Time comes from `clock()`.
- Statuses exactly `laeuft fund zu offen warn`; symbols `▶ ✔ ✖ ? ⚠`, `·` for a started step without result.
  Colours: TEAL laeuft, YELLOW fund, RED warn, DIM offen and `·`, none for zu.
- File keys exactly `zeit ziel weg was warum gesendet antwort bedeutung status`; text through `clean(value, 200)`.
- Unchanged: the board format, `hook()`, `add_idea()`, `bar_json()`/`bar_focus()`, the overview and the `f` view.
- Commits: `git commit --no-gpg-sign` (never sign; the owner signs on delivery). No push.

## Review Focus

1. Two sessions in one lab folder write the same step file at once → lines never interleave: one `os.write()` per
   line on an `O_APPEND` descriptor (Task 1 test: two writers in parallel, 50 lines each, every line parses).
2. A step file of many MB after a long engagement → the view and the bar read only the tail (Task 1 test: 510
   steps, `read_steps` returns the last 500).
3. Step text with ESC sequences, newlines, `<` and `&` → never raw in the terminal (Task 1 test via `clean`), escaped
   in Waybar (`escape = true`, Task 4).
4. Stream mode on → the bar shows no step text (Task 4 test).
5. An offen seed or a warn between a step's start and its finish → still one row, the way keeps its status
   (Task 2 tests).

---

### Task 1: Step file, writer and reader

**Files:**
- Modify: `tools/lage.py` (new code after `board_entries()` ~line 614; dispatch in `main()` before the `bar` branch ~line 871; module docstring gains one usage line)
- Test: `tools/lage.test.sh`

**Interfaces:**
- Produces: `STEPS: dict[str, str]` status → symbol (in the order above); `STEP_KEYS: tuple[str, ...]` (the nine keys);
  `steps_path(session: dict) -> Path` (`board_of(session)` with `.md` replaced by `.schritte.jsonl`, so `lage.md` →
  `lage.schritte.jsonl`); `own_session() -> dict | None` (walk up parent pids from `os.getpid()` with the `procs()`
  table to a live pid of `sessions()`); `read_steps(path: Path) -> list[dict]` (oldest first; each dict has every
  STEP_KEYS key as a clean str plus `ts`: aware datetime from `parse_ts(zeit)` or None; reads at most the last
  262144 bytes, keeps the last 500 lines, skips bad JSON, non-dicts, unknown status, empty `was`; never raises,
  missing file = `[]`); `write_step(argv: list[str]) -> int`.

- [ ] **Step 1: Write the failing tests**

```bash
# test_schritt_new: a new step, every key, status laeuft, the session's own file
fresh; session $$ $s1 src-a "$HOME/w"
lage schritt "Port 80 prüfen" --warum "w1" --gesendet "g1" --ziel "Router" --weg "Web"
sf=$HOME/.local/state/lage/$s1.schritte.jsonl
[[ $(wc -l <"$sf") -eq 1 ]]
jq -e '.zeit == "2026-11-15T14:12:20+00:00" and .status == "laeuft" and .was == "Port 80 prüfen" and .warum == "w1"
  and .gesendet == "g1" and .ziel == "Router" and .weg == "Web" and .antwort == "" and .bedeutung == ""
  and (keys | length) == 9' "$sf"
# test_schritt_finish: without WAS the newest non-offen step is copied, given fields win, status kept unless given
lage schritt "Y später" --weg "Seriell" --status offen
lage schritt --antwort "teil"
lage schritt --antwort "a1" --bedeutung "b1" --status fund
[[ $(wc -l <"$sf") -eq 4 ]]
jq -se '.[2].status == "laeuft" and .[2].was == "Port 80 prüfen" and .[2].antwort == "teil"
  and .[3].status == "fund" and .[3].warum == "w1" and .[3].gesendet == "g1" and .[3].weg == "Web" and .[3].bedeutung == "b1"' "$sf"
# test_schritt_errors: nothing to change, no session, a wrong status; nothing is written then
fresh; session $$ $s1 src-a "$HOME/w"
rc=0; lage schritt --antwort x 2>"$t/err" || rc=$?; [[ $rc -eq 1 && $(<"$t/err") == *"noch kein Schritt"* ]]
fresh; session 999999 $s1 src-a "$HOME/w"
rc=0; lage schritt "x" 2>"$t/err" || rc=$?; [[ $rc -eq 1 && $(<"$t/err") == *"keine Claude-Sitzung"* && ! -e $HOME/.local/state ]]
fresh; session $$ $s1 src-a "$HOME/w"; rc=0; lage schritt "x" --status info 2>/dev/null || rc=$?; [[ $rc -eq 2 ]]
# test_schritt_clean: first line only, control characters as ?, cut to 200 with …; an empty WAS counts as missing
sf=$HOME/.local/state/lage/$s1.schritte.jsonl
lage schritt "$(printf 'a\033[2Jb\nzweite')" --warum "$(printf 'x%.0s' {1..300})"
jq -e '.was == "a?[2Jb" and (.warum | length) == 200 and (.warum | endswith("…"))' "$sf"
# test_schritt_lab: a session started inside a lab folder writes next to the lab board
fresh; mkdir -p "$HOME/src/sec/live/x/sub"; session $$ $s1 src-a "$HOME/src/sec/live/x/sub"
lage schritt "im Lab"; [[ -s $HOME/src/sec/live/x/.claude/lage.schritte.jsonl ]]
# test_schritt_parallel (Review Focus 1): two writers at once never interleave a line (lines longer than 150 bytes)
fresh; session $$ $s1 src-a "$HOME/w"
for w in a b; do (for i in $(seq 25); do lage schritt "$w$i" --warum "$(printf 'y%.0s' {1..150})"; done) & done; wait
[[ $(jq -c . "$HOME/.local/state/lage/$s1.schritte.jsonl" | wc -l) -eq 50 ]]
```

plus one `python3 -B - "$here"` block (as `test_states_follow` does) for `read_steps`: a file with 510 good lines
(`was` = `s0` … `s509`), one broken line, one line with status `info`, one non-dict line in between → 500 records,
the first `was == "s10"`, every record has `ts` set; a missing file → `[]`.

- [ ] **Step 2: Run the tests, see them fail** — `bash tools/lage.test.sh` → `FAIL at line …` in test_schritt_new.

- [ ] **Step 3: Implement** `STEPS`, `STEP_KEYS`, `steps_path`, `own_session`, `read_steps`, `write_step` and the
  `main()` dispatch `if sys.argv[1:2] == ["schritt"]: return write_step(sys.argv[2:])`. `write_step`: argparse with
  `prog="lage schritt"`, positional `was` (`nargs="?"`), `--warum --gesendet --antwort --bedeutung --ziel --weg`,
  `--status` with `choices=tuple(STEPS)`; messages `lage: keine Claude-Sitzung über diesem Befehl` and
  `lage: noch kein Schritt zum Ändern` on stderr with exit 1; `zeit = clock().isoformat(timespec="seconds")`;
  create the folder, then one `os.write()` on `os.open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)`,
  `json.dumps(record, ensure_ascii=False) + "\n"`. Silent on success.

- [ ] **Step 4: Run the tests and flake8** — both clean, test ends with `ok`.

- [ ] **Step 5: Commit** — `git add tools/lage.py tools/lage.test.sh && git commit --no-gpg-sign -m "feat(lage): sessions report steps with lage schritt"`

### Task 2: Work view

**Files:**
- Modify: `tools/lage.py` (`frame()` ~line 736, `foot_line()` ~line 727, `main()` argparse + loop ~line 868-930)
- Test: `tools/lage.test.sh`

**Interfaces:**
- Consumes: Task 1's `read_steps`, `steps_path`, `STEPS`.
- Produces: `step_rows(steps: list[dict]) -> list[tuple[dict, int]]` (newest first: offen dropped, then a laeuft
  whose next remaining line has the same `was` dropped, then rows with equal `(status, weg, was)` merged into the
  newest one with a count); `way_rows(steps: list[dict]) -> list[tuple[str, str]]` (`(weg, status)` in order of first
  appearance; status = newest fund/zu/offen of that weg, else offen); `step_source(followed: dict | None) ->
  tuple[dict | None, list[dict]]` (the followed session's steps when its file has any record, else the live session
  whose newest record is newest, else `(None, [])`); `work_lines(src, width: int, room: int) -> list[str]`;
  `frame(..., src=None)`: with `src` it returns `work_lines(src, cols(), max(rows() - 1, 1))`;
  `foot_line(width, keys, left=None)`: `left` replaces the key text. CLI flag `--arbeit` (start in the work view).

- [ ] **Step 1: Write the failing tests** (all with `lage --dir "$HOME/w" --once --arbeit`, `COLUMNS=46`)

```bash
# test_work_three_steps (Done 1): three steps, the newest on top with all five fields, the older ones with ← and =
fresh; session $$ $s1 src-a "$HOME/w"
lage schritt "Port 80 prüfen" --warum "w1" --gesendet "g1"; lage schritt --antwort "a1" --bedeutung "b1" --status zu
lage schritt "Login testen" --warum "w2"
lage schritt "NTP fragen" --ziel "Router" --warum "w3" --gesendet "g3" --antwort "a3" --bedeutung "b3" --status fund
out=$(lage --dir "$HOME/w" --once --arbeit)
[[ $(head -n 1 <<<"$out") == "LAGE  src-a · ARBEIT"*"14:12" && $out == *$'\nZIEL  Router\n'* ]]
[[ $out == *"✔ NTP fragen"* && $out == *"warum   w3"* && $out == *"sendet  g3"* && $out == *"←       a3"* && $out == *"=       b3"* ]]
[[ $out == *"· 14:12  Login testen"* && $out == *"✖ 14:12  Port 80 prüfen"*$'\n  ← a1\n  = b1'* ]]
[[ $out != *"Port 80 prüfen"*"Port 80 prüfen"* ]]          # the finish hides its start line
widest <<<"$out" | { read -r w; ((w <= 46)); }
# a running top step says that no answer is there yet, and how long it runs
lage schritt "Scan" --warum "w4"; out=$(LAGE_NOW=2026-11-15T14:13:00Z lage --dir "$HOME/w" --once --arbeit)
[[ $out == *"▶ Scan"*"seit 40 s"* && $out == *"←       noch keine Antwort"* ]]
# test_work_merge (Done 2): 20 equal warnings between other steps are one row
fresh; session $$ $s1 src-a "$HOME/w"
for i in $(seq 20); do lage schritt "IPv4 fällt aus" --status warn --bedeutung "Aussetzer"; ((i % 7)) || lage schritt "Schritt $i" --status zu; done
out=$(LINES=40 lage --dir "$HOME/w" --once --arbeit)
[[ $(grep -c "IPv4 fällt aus" <<<"$out") -eq 1 && $out == *"IPv4 fällt aus  ×20"* ]]
# test_work_ways (Review Focus 5): a warn never changes a way, the first open way not running is next
fresh; session $$ $s1 src-a "$HOME/w"
lage schritt "X1" --weg "Web" --status fund; lage schritt "Y" --weg "Seriell" --status offen
lage schritt "Z" --weg "Chip" --status offen; lage schritt "Aussetzer" --weg "Web" --status warn
lage schritt "Chip lesen" --weg "Chip"
out=$(lage --dir "$HOME/w" --once --arbeit)
[[ $out == *$'\nWEGE  ✔ 1  ? 2\n▶ Chip\n? Seriell'*"→ als Nächstes"* && $out == *"✔ Web"* && $out != *"⚠ Web"* ]]
# test_work_empty and test_work_source: no steps; the followed session has none, another live one has
fresh; session $$ $s1 src-a "$HOME/w"; out=$(lage --dir "$HOME/w" --once --arbeit); [[ $out == *"Noch keine Schritte"* ]]
live; session $pid bbbbbbbb-2 src-b "$HOME/empty"; mkdir -p "$HOME/.local/state/lage"
echo '{"zeit":"2026-11-15T14:00:00+00:00","ziel":"","weg":"","was":"fremd","warum":"","gesendet":"","antwort":"","bedeutung":"","status":"laeuft"}' \
  >"$HOME/.local/state/lage/bbbbbbbb-2.schritte.jsonl"
out=$(lage --dir "$HOME/w" --once --arbeit); [[ $(head -n 1 <<<"$out") == "LAGE  src-b · ARBEIT"* && $out == *"▶ fremd"* ]]
# test_work_small: a small pane keeps head, top and foot and drops older steps first (+N ältere)
```

(For test_work_small write 6 finished steps with weg, `LINES=14`: at most 13 lines, line 1 the head, the last line
the foot ` s Stopp  ? Frage  i Idee  a zurück`, `+… ältere` present, `WEGE` present.)

- [ ] **Step 2: Run, see them fail.**

- [ ] **Step 3: Implement** `step_rows`, `way_rows`, `step_source`, `work_lines` and the wiring. Layout and rules are
  the design's; pinned details: the top step's field lines are `  warum   …`, `  sendet  …`, `  ←       …`,
  `  =       …` (only fields that are set; `←       noch keine Antwort` dim while it runs), each wrapped to at most 2
  lines; its first line is `<sym> <was>` plus `  ×N` when merged, with `seit <ago>` (laeuft) or `HH:MM` right-aligned. Older rows: `<sym> <HH:MM or DD.MM.>  <was>`
  plus `  ×N` when merged, then `  ← …` and `  = …` cut to one line each; a row is shown whole or not at all, the rest
  is counted in `+N ältere`. `·` marks a laeuft row that is not the newest. WEGE only when a record has a `weg`:
  header with the non-zero counts of `✔ ✖ ?` in that order, then the running way first (`▶`), then the next way
  (suffix `→ als Nächstes`, right-aligned when it fits), then the rest in order of first appearance; at most 6 rows,
  then `+N weitere`. Rules (`─` × width, GREY) between the blocks; WEGE gets its room before the older rows. Empty
  state: `Noch keine Schritte.` and `Sitzungen melden sie mit: lage schritt`. Head: `LAGE  <label> · ARBEIT` with
  the time right-aligned, `label()` of the source session. Foot via `foot_line(width, True, " s Stopp  ? Frage  i Idee  a zurück")`.
  Main loop: `--arbeit` sets the start view; key handling is Task 3, so here only `--once` must work.

- [ ] **Step 4: Run the tests and flake8.**

- [ ] **Step 5: Commit** — `feat(lage): work view shows the steps of a session (key a)`

### Task 3: Keys, the way back and the bar's switch request

**Files:**
- Modify: `tools/lage.py` (`wait()` ~line 799, `main()` loop)
- Test: `tools/lage.test.sh` (pty tests modelled on `test_enter`)

**Interfaces:**
- Consumes: Task 2's `step_source`, `step_rows`, `frame(..., src=)`; `add_idea`, `board_of`.
- Produces: `wait(seconds, session, src=None) -> bytes` now also returns `b"a"`; `request_path() -> Path | None`
  (`$XDG_RUNTIME_DIR/lage-arbeit`, None without the variable).

- [ ] **Step 1: Write the failing tests**
  - `test_work_keys` (pty, `python3 prog --dir folder`): first frame shows the overview foot; key `a` → a frame with
    `ARBEIT`; key `s`, then `Grund\r` → the board of the step's session has a line `- [ ] … Stopp bei „Scan“: Grund`;
    key `?`, `\r` (empty) → no new line; key `?`, `wieso?\r` → `Frage zu „Scan“: wieso?`; key `i`, `x\r` →
    `Idee zu „Scan“: x`; key `a` → the overview again; SIGINT → exit 0.
  - `test_work_request`: `touch "$XDG_RUNTIME_DIR/lage-arbeit"` → `lage --dir "$HOME/w" --once` shows `ARBEIT`;
    `touch -d '-1 hour' "$XDG_RUNTIME_DIR/lage-arbeit"` → the overview; without `XDG_RUNTIME_DIR` → the overview.

- [ ] **Step 2: Run, see them fail.**

- [ ] **Step 3: Implement.** In `wait()`, `a` ends the wait like `f`; with `src` and a top step, `s`, `?`, `i` ask one
  line (`input("Stopp (Grund, Enter sendet): ")`, `input("Frage: ")`, `input("Idee: ")`) and call
  `add_idea(board_of(src_session), text, clock())` with `Stopp bei „<was>“[: Grund]`, `Frage zu „<was>“: …`,
  `Idee zu „<was>“: …`; an empty Frage/Idee adds nothing; EOF/Ctrl-C/OSError cancel quietly as for `i` today. Without
  `src`, keys behave as before. Main loop: `view` in `overview|full|work`; `f` toggles full, `a` toggles work; leaving
  the full view still records `seen`; `asked = time.time() - 10` at start, each round a `request_path()` mtime newer
  than `asked` switches to work and becomes the new `asked`; in work view the loop computes `src = step_source(session)`
  and passes it to `frame()` and `wait()`.

- [ ] **Step 4: Run the tests and flake8.**

- [ ] **Step 5: Commit** — `feat(lage): Stopp, Frage and Idee for a step; the bar can ask for the work view`

### Task 4: Bottom bar field

**Files:**
- Modify: `tools/lage.py` (new `bar_step()`, `bar_step_json()`, `bar_step_open()`, `streaming()`; dispatch in `main()` before the generic `bar` branch)
- Modify: `modules/user/desktop/waybar.nix` (bottom bar `modules-left` ~line 281, module next to `custom/target` ~line 313, CSS ~lines 509-520 and 643-661)
- Test: `tools/lage.test.sh`

**Interfaces:**
- Consumes: Task 1-3 (`read_steps`, `steps_path`, `step_rows`, `request_path`), `focus()`, `sessions()`, `label()`.
- Produces: `lage bar schritt` (one JSON line) and `lage bar schritt --open` (exit 0).

- [ ] **Step 1: Write the failing tests** (`bs() { lage bar schritt; }`; times via `LAGE_NOW`)
  - running step → `{"text": "▶ Scan", "class": "laeuft", ...}` and the tooltip holds the session label and warum.
  - fund at 14:12:20 then a new laeuft at 14:12:30: at 14:13:00 the text is `✔ …` (class fund); at 14:15:00 `▶ …`.
  - a warn and a fund both younger than 120 s → the warn.
  - newest step older than 30 min → `{"text": ""}`; no step or no live session → `{"text": ""}`.
  - `touch "$XDG_RUNTIME_DIR/bar-stream-manual"` → text is only the symbol, the output holds no `was` and no warum.
  - a `was` of 60 characters is cut to 40 with `…`.
  - `--open` with the `$t/fbin` stub extended by `activeworkspace` (prints `{"id":3}`) and a fake
    `$HOME/.local/bin/hypr-cockpit` that writes a marker file: the step session's window gets the focus dispatch,
    `$XDG_RUNTIME_DIR/lage-arbeit` exists, the marker appears (poll up to 2 s); with
    `$XDG_RUNTIME_DIR/hypr-cockpit/3` present no marker; with no window for the session no marker and exit 0.

- [ ] **Step 2: Run, see them fail.**

- [ ] **Step 3: Implement.** `bar_step() -> tuple[dict | None, dict | None]` (session, record) per the design: only
  live sessions, each step file once, candidates = `step_rows()` records, newest by `ts`; None when the newest is
  older than 1800 s; a fund/warn candidate at most 120 s old wins (warn first, then newest). `bar_step_json()`:
  `text = f"{sym} {clean(was, 40)}"`, `class = status`, tooltip lines: `<label>` (+ ` · <ziel>`), `Weg: …`,
  `warum: …`, `sendet: …`, `← …`, `= …` (set fields only); `streaming()` (either flag file in `$XDG_RUNTIME_DIR`)
  → `{"text": sym, "class": status, "tooltip": ""}`. `bar_step_open()`: focus the picked session's window; touch
  `request_path()`; only when `focus()` returned 0 and `$XDG_RUNTIME_DIR/hypr-cockpit/<active workspace id>` is
  missing, start `~/.local/bin/hypr-cockpit` detached (`subprocess.Popen`, `start_new_session=True`, DEVNULL);
  always exit 0. Errors in `bar schritt` print `lage: …` to stderr and `{"text": ""}` (as `bar` does).
  waybar.nix: `"custom/schritt"` after `"custom/target"` in the bottom bar's `modules-left`; module
  `exec = "${lage} bar schritt"`, `return-type = "json"`, `interval = 2`, `signal = 8`, `escape = true`,
  `on-click = "${lage} bar schritt --open"`, with a one-line comment. CSS: `#custom-schritt` joins the shared
  padding/border selector list and the bottom bar's dim list; `#custom-schritt.laeuft { color: base0C }`,
  `#custom-schritt.fund { background-color: base0A; color: base00 }`, `#custom-schritt.warn { background-color: base08; color: base00 }`.

- [ ] **Step 4: Run the tests, flake8, and build the Waybar config:**
  `nix eval --json '.#nixosConfigurations.bandit.config.home-manager.users.vino.programs.waybar.settings.bottomBar.modules-left'`
  → `["group/admin","custom/target","custom/schritt"]`; `alejandra -c modules/user/desktop/waybar.nix` clean. (The full
  laptop build runs in Task 5 on the laptop's own tree.)

- [ ] **Step 5: Commit** — `feat(waybar): the newest step of a session in the bottom bar`

### Task 5 (lead session, not a worker): delivery

- Laptop tree `~/src/bandit-nix-arbeit-laptop` (detached at 9925636 = what the laptop runs) + the four commits
  cherry-picked unsigned; `nix build` of `nixosConfigurations.bandit.config.system.build.toplevel` there.
- Owner script `~/lage-arbeit-deploy.sh`: check both trees' HEADs; `git rebase -S origin/main` + `git push origin
  HEAD:main` in `~/src/bandit-nix-arbeit`; `nh os switch .` in the laptop tree; add the CLAUDE.md line (backup,
  idempotent); print "Super+C zweimal". Queue with `liefern add`.
- Live check after delivery: three `lage schritt` calls from this session, visible in the Cockpit within 5 s; a bar
  click; tell the sec session how to switch its prototype.
