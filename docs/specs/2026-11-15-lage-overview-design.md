# lage overview — design (short)

Approved by the owner 2026-11-15 (browser mockup, choice A "Ja, so bauen").
Builds on `docs/specs/2026-11-15-claude-lage-design.md`; its constraints still hold.

## Why

The Cockpit pane was a long text list plus a shell below. The owner (dyslexia + ADHD) found both
unnecessary and wants a glanceable overview: what Claude does, who waits, their own tasks, new items.

## Goals

- Main view, fixed order:
  ```
  LAGE  <session> <title>                    HH:MM
  ▶ JETZT   <step> (seit …)
  ! WARTET  <other session>: <waitingFor>     (red; only when another session waits)
  DEINE AUFGABEN  N                           (owner's open tasks, max 5, "+N weitere")
  LOG  (was Claude macht)                     (last steps, newest first)
  NEU  2 Funde · 1 für dich · 0 Ideen
  i = Idee   f = alles zeigen
  ```
- `f` toggles the full board view (today's board sections); `f` again returns.
- The pane is lage only; the shell split goes away.

## Non-goals / anti-goals

- No controlling Claude from the pane beyond ideas (unchanged).
- No system logs (journalctl): pop-ups and Grafana already show those; doubling is noise.
- Not a long list again: at tall heights the bottom stays empty instead of filling with text.

## Approaches

1. **Rework `tools/lage.py` in place (chosen).** Stdlib Python, existing transcript, board and
   session code stay; smallest diff.
2. Waybar/eww widget or a web page: new stack, no `i`/`f` keys in the Cockpit.
3. A TUI library (Textual): new dependency for boxes we can draw with text.

## Decisions (architect, Fable)

- **Rows** (room = LINES-1). Never dropped: header, JETZT, WARTET (≤3 lines, third `+N weitere`),
  tasks heading with count, NEU line. The rest in this order: LOG 3 → tasks 5 → LOG up to 8 →
  `i = Idee` line → 3 blank lines; shrink in reverse. One line per entry (`clean(x, width)`); wrapping
  only in the `f` view.
- **LOG**: a step = a `tool_use` in the main transcript, text from the existing JETZT mapping; newest
  first, the running step included. Collapse when inserting: same text, or the same verb
  (liest/sucht/ändert) back to back → newest name + ` +N`, newest time. Never collapse helpers. Time
  `HH:MM`, another day `TT.MM.`. Helper transcripts are not read.
- **Tasks**: `https://memory.tail7facc9.ts.net/notes/lagebild.md`, section `## Waiting for a human`
  only (`N. project (store): text (who) [date]`). Background thread, every 300 s from the last try,
  timeout 3 s, read ≤ 64 KiB, ≤ 10 lines; show only the text, only rows whose who is `vino` or empty;
  `10+` when the list is full. Cache `~/.local/state/lage/aufgaben.md` (atomic write); cache older
  than 15 min shows `(Stand HH:MM)`; no cache shows `nicht erreichbar`. Task text is foreign data:
  only through `clean()`, never into the hook output or the board. `LAGE_TASKS_URL` overrides the
  URL; empty = off (tests need no network). `--once` waits ≤ 3 s for the thread.
- **`f`**: a toggle, JETZT and WARTET stay visible in it. Closing it sets `seen = now`; NEU =
  newer than max(owner's last prompt, seen), in memory only. NEU line: new Funde · new Für dich ·
  open Ideen; a new `!` item starts the line with a highlighted `!`.
- **Delete**: the SITZUNGEN list (replaced by WARTET: only waiting sessions other than the followed
  one), `cockpitSession` in `scripts.nix` (the pane runs `lage` directly in kitty).

## Left to the builder

Names of new functions and flags (a `--full` flag for tests is suggested), exact test split.

## v2 look (approved 2026-11-15, browser choice A)

Colours from the theme (headings teal, times grey, waiting red, NEU yellow, projects purple), blank lines instead of rules, header time without "Stand", `▶ <text>  seit …` instead of `JETZT ▶`, `! <name> wartet: …` without the topic, AUFGABEN in two columns with 3 rows, LOG with 4 steps, tool names in plain German (memory, web, the board file). Bash descriptions in German come from a rule in the owner's global CLAUDE.md.

## v3 (owner 2026-11-15: "half of the page is not being used", wants a terminal for deploys)

The shell split comes back below lage (`cockpitSession`, kitty `hsplit --bias=35`), which replaces
the "lage only" goal and the empty-bottom anti-goal. Rows are filled in this order: LOG 3, the key
line, the blank lines between the parts, then up to 5 task rows (`+N weitere` as the 6th line), then
LOG up to 8 steps. A short pane loses the extra rows before it loses the blank lines.

The waiting line names a session by its tab title (`custom-title` from `/rename`, else the newest
`ai-title`, cut to 18), else by its name, else by the first 6 characters of its id (owner: "src-06"
matched no tab).
