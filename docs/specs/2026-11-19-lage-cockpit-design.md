# Cockpit window overhaul: design (2026-11-19)

Short design, approved by the owner on 2026-11-19 (variant B by click in the visual companion, "jup hört sich
gut an und lass font size"). Architect: Fable. Lead: src-c5. To be moved to `docs/specs/` in bandit-nix by the
session that builds it.

## Intent

The Cockpit (Super+C: `lage` on top, a small shell below) answers two questions and nothing else:
"What must I do now?" and "What are my sessions doing?"

Why: the owner said the window has too much text, his own next steps get lost, he cannot see what each Claude
session is doing, and look and handling need work. He has dyslexia and ADHD: few words, the next step first,
long material elsewhere.

## Goals, non-goals, anti-goals

- Goals: his next three steps on top; one fixed line per live session with an honest state; the full board one
  key away; the Grey Console colours.
- Non-goals: a phone line (the laptop has no data about the phone), ticking steps off from lage (only sessions
  write boards), starting deploys from lage (sudo, GPG and the finger need the shell below; `liefern` is 7
  letters), scrolling, mouse, digit keys, a bigger font (owner: keep size 16).
- Anti-goals: invented precision (a state the data does not prove); silently dropping a `!` line.

## What it shows (variant B, pane 56 columns x 26 rows today)

```
LAGE                                               09:47   teal / dim
 DU                                                        yellow, bold
 1  liefern · 3 warten                                     yellow
 2  Brief an die Datenschutzbehörde                        red (!)
 3  Mrija                                                  red (!)
    +6 weitere · f                                         dim
────────────────────────────────────────────────────────   #303034
 ● src-c5  arbeitet  prüft Bot-Fixes                       teal
 ○ src-13  ruht  12 min                                    dim
 ○ src-6f  ruht  41 min                                    dim
────────────────────────────────────────────────────────   #303034
 f alles   i Idee   ⏎ zur Sitzung            Woche 38 %    dim
```

Colours: yellow #fdb827 = your turn; red #ed4749 = important and open; teal #00a99d = session works; dim
#848488 = resting; separators #303034; text #d0d0d0; background #0d0d0e.

## Rules

- Order of the DU lines, fixed: 1. `liefern` when its queue (`~/.local/state/liefern/warten/`) is not empty,
  with the count; 2. a session whose status is `waiting` ("▲ wartet auf dich", yellow, with `waitingFor`);
  3. open `!` lines under "Für dich" (no "→" yet) from the boards of live sessions, newest first.
- A step's text is cut at the first ": " or ". ". At most three steps; the rest is counted as "+N weitere · f".
- Sessions, from `~/.claude/sessions/*.json` and the log: working (`busy`, plus the last tool step), waiting
  for him (only `status: waiting`), resting (`idle`, plus age), helpers working (n), ended (process gone).
  `idle` reads "ruht". Today `jetzt()` shows `idle` as "wartet auf dich": that is wrong in the overview and
  must not be carried over. `jetzt()` itself stays as it is, because the bar and `wartet_lines` depend on it.
- Names: the session label (`label()`, tab title); no invented role names.
- Keys: `f` full board (as today), `i` idea (as today), Enter jumps to the session that waits, else to the one
  that works (the logic of `lage bar --focus`).
- Footer: `seven_day.used_percentage` from `~/.cache/claude-hud/usage.json`; `five_hour` only when not null.

## Changes

`tools/lage.py`:
1. New `du_lines()`: count the liefern queue, waiting sessions, open `!` lines over all boards (uses
   `parse_board`, `board_path`).
2. New `session_rows()`: uses `sessions()`, `session_state()`, `label()`.
3. `frame()`: replace the overview branch by head, DU, sessions, foot. The `full` branch stays.
4. `wait()`: Enter calls the focus logic of `bar_focus()`.
5. Delete `log_lines` and `task_lines` if nothing calls them afterwards (grep first).

`tools/lage.test.sh`: new overview cases; the cases for `--full`, `--idea` and `bar` stay green unchanged.

`modules/user/desktop/hyprland/scripts.nix`: `--bias=35` to about 25 in `cockpitSession` (more rows for lage).
Nothing else in `hypr-cockpit`.

## Invariants

Never read the `.key` files in `~/.claude/sessions/`. lage writes only ideas into a board. At most `rows()-1`
lines. A `!` line is never dropped silently, it is counted in "+N".

## Check

`sh tools/lage.test.sh`, then `COLUMNS=56 LINES=26 lage --once` against the mock-up. The flake check targeted,
never the full one (OOM on the laptop).

## Open

- Whether old `!` lines are reliably closed with "→". If not, "+N" stays too high. Cheapest test: count
  `!` lines against lines with "→" over `~/.local/state/lage/*.md`.
- Owner decision pending: a rule for sessions that "Für dich" lines start with at most 5 words, then ": ".
  It would be a line in his `~/.claude/CLAUDE.md`, which only he approves. The design works without it.
- Not read by the architect: `bar_focus()`, `hypr-cockpit` from line 110, `lage.test.sh`, the three older
  lage design documents.
