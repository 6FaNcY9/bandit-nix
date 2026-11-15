# Lage: a live view of what Claude is doing (design)

Date: 2026-11-15 · Branch `feat/claude-lage` (worktree `~/src/bandit-nix-lage`)
Approach picked by the owner: **B, the right pane of the Cockpit (Super+C)**, plus the same view as
one more pane in `pt dash`.

## Intent

The owner is a white-hat security network admin with dyslexia and ADHD who sits far from the screen
and works with Claude Code in kitty on the laptop `bandit`. In the owner's words: while we work there
is too little information about **what exactly Claude is doing right now** and **what the most
important data is**. In a real security engagement the owner must know quickly **what Claude has
found**, and wants to be pointed at **what may have been overlooked on both sides**: things Claude
misses because it is an LLM, and things the owner misses because humans do. No real engagements yet;
first comes practice on realistic CTFs, and those runs are the first real test of this view.

Success: one look at the right side of the screen tells the owner what Claude is doing now, whether
it is waiting, what was found, what was skipped or only guessed, and what Claude wants checked. The
owner can drop in an idea without interrupting Claude, and Claude picks it up.

## Goals

1. Super+C with a Claude session in the work window opens the view `lage` in the Cockpit's right pane.
2. A live line, **JETZT**: the tool Claude is running and its plain-language description, or
   `wartet auf dich` when Claude has finished its turn.
3. **NEU** marks on everything that appeared since the owner's last message to that session.
4. A board with four sections: Funde (findings), Ungeprüft (skipped, assumed or guessed), Für dich
   (things Claude wants the owner to check), Deine Ideen (the owner's). One board per session; in a
   sec lab folder one board per lab folder, so a new session continues it (owner, 2026-11-15).
5. One key in the pane adds an owner idea; Claude sees it at its next tool call or prompt at the
   latest, works it, and ticks it with a short result.
6. The same view as an extra pane in `pt dash` (sec repo).
7. A **SITZUNGEN** block at the bottom of the pane: every running Claude session in one line, with
   name, topic, and whether it waits for the owner and for what. The owner runs several sessions
   and loses track of which one needs what (owner, 2026-11-15).

## Non-goals

- No web page and no phone view (approach C, maybe later).
- No controlling Claude from the pane beyond adding ideas: no stop, approve or prompt buttons.
- No change to how Claude asks for permission; the live lab's ask-mode stays as it is.
- Not part of this work, tracked separately: merging the global `pt` shim (`feat/sec-lab-shim`), the
  missing nix-index database error, the long direnv variable list when entering `~/src/sec`.
- No history browser. The transcript stays the full record.

## Anti-goals (a failure even if it works)

- The pane takes focus or becomes master. The existing Cockpit rules must keep holding.
- Loot leaves the engagement folder. A board inside `~/src/sec/live/<engagement>/` must never reach
  git, basic-memory, the lab or any other machine.
- A wall of text, raw JSON, or small text. The pane fits one screen at the normal font (0xProto 18),
  short lines, simple German labels.
- A view that lies. If it cannot find the session, or the data is old, it says so
  (`kein Claude im Hauptfenster`, `Sitzung beendet`, `Stand vor 3 min`).
- Board upkeep that costs Claude many tokens or slows the work down (one short line per entry).

## Constraints and facts (checked 2026-11-15)

- Laptop config: bandit-nix home-manager under `modules/user/`. House style for small tools is a
  bash + jq script, see `hypr-cockpit` in `modules/user/desktop/hyprland/scripts.nix:37-85`.
- Cockpit today (Hyprland 0.56.2): per-workspace master layout; the work window (most recently
  focused tiled non-log window) becomes master; a kitty with class `cockpit-log` running
  `journalctl -f` opens on the right only when the workspace has one tiled window or group; toggle
  off closes every `cockpit-log` window. `rules.nix` keeps `cockpit-log` from taking focus or joining
  a tab group.
- Claude Code: `~/.claude/sessions/<pid>.json` holds `pid`, `sessionId`, `cwd` (the **start**
  folder; the transcript's own `cwd` field moves as the session works in other repos), plus
  `status` (seen: `busy`, `shell`) and `statusUpdatedAt`. Transcripts:
  `~/.claude/projects/<start cwd with "/" and "." replaced by "-">/<sessionId>.jsonl`. Entries of
  `type: "assistant"` carry `message.content[]` with `tool_use` items (`name`, `input`; Bash has a
  human `input.description`) and `message.stop_reason` (`tool_use`, `end_turn`, also `refusal`).
  Some entry types (`mode`, `atis-latch`, `tools-used`, …) have no `timestamp` and are often the
  newest line: skip them.
- Owner prompts: `type: "user"` entries that are not `isMeta`, not a `tool_result`, and not a
  harness string (`<task-notification>`, `<command-message>`, compact summary). Content is a string
  or an array (`text` + `image` when a screenshot is attached).
- Helpers (subagents) write their own transcripts under `<sessionId>/subagents/agent-*.jsonl`; the
  main transcript holds none of their steps.
- Each Hyprland kitty window has its own pid (`.kitty-wrapped` → zsh → `claude`), checked live.
  In sec labs `pt ctf|live <name>` starts **tmux** in the lab folder (`nix/lib/labs.sh`), so there
  Claude is a child of the tmux server, not of kitty.
- `~/.claude/hooks/memory-save.sh:44-69` sends user and assistant text of every session to
  basic-memory on the lab, with no exception for `live/`. That breaks the live lab rule "loot never
  in basic-memory" today, independent of this view.
- `~/.claude/CLAUDE.md` and `~/.claude/settings.json` are plain files the owner edits, not managed by
  Nix. Existing hooks live in `~/.claude/hooks/` (e.g. `memory-save.sh`).
- The sec repo's `pt dash` is a tmux dashboard (`nix/lib/dash.sh`, branch `feat/sec-labs`, not
  merged yet). It still finds the engagement under the old `engagements/<name>` folder
  (`nix/lib/core.sh:169-181`), not under the lab folders. Lab contents are git-ignored, but the sec
  `.gitignore` re-includes `live/.claude/`, so `.claude/lage.md` needs its own ignore rule.
- The owner deploys (`nh os switch`). Claude never deploys.

## Approaches

| | What | Trade-off |
|---|---|---|
| A | One more pane in `pt dash` | Smallest, but only in security work |
| **B (picked)** | Right pane of the Cockpit (Super+C) | Every kind of work, laptop only |
| C | A web page like the memory page | Phone too, most work |

The owner picked B on 2026-11-15; the same `lage` program also runs as a pane in `pt dash`, so A
comes almost free. C stays open for later.

## Design

### What the pane shows

```
LAGE  ctf/box1                     Stand 14:12
JETZT ▶ prüft die Webseite der Übungs-Box
        Bash · seit 20 s
──────────────────────────────────────────────
FUNDE  3  (1 neu)
 NEU !  Admin-Login ohne Sperre  /login
     ·  Port 22 offen, OpenSSH 9.6
UNGEPRÜFT  2
     ·  UDP nicht gescannt
     ·  Login-Schwäche nur vermutet
FÜR DICH  1
 NEU ·  Ist 10.10.10.7 im Scope?
DEINE IDEEN  1 offen
     ·  [ ] Cookie anschauen
──────────────────────────────────────────────
SITZUNGEN
 !  src-c8  Bot-Menü     wartet: Soll ich es ausrollen?
 ▶  src-4c  CTF box1     arbeitet
    src-fb  aiia         arbeitet
──────────────────────────────────────────────
i = Idee eintragen
```

- Header: short form of the session's working directory, time of the last refresh.
- JETZT, from the newest non-sidechain transcript entry:
  - `tool_use`: Bash shows `input.description`; other tools a short German form
    (`liest <file>`, `ändert <file>`, `sucht <pattern>`, `Helfer: <description>` for Agent, else the
    tool name). Plus the age (`seit 20 s`).
  - `end_turn`: `wartet auf dich`, highlighted, but only when no helper of this session is still
    running; otherwise `Helfer arbeiten (N)`.
  - The session file's `status` may be the cheaper source for busy/idle; the builder picks.
- Sections come from the board file. `!` at the start of an entry means important and is
  highlighted. Long lines wrap; the pane never scrolls sideways.

### Which session

The program follows the Claude session in the Cockpit's master window: master window pid →
descendant process `claude` → `~/.claude/sessions/<pid>.json` → `sessionId` and `cwd` → transcript.
It re-resolves on every refresh, so switching tabs in a master tab group follows along. If the
kitty runs a tmux client (sec labs), the walk continues from the tmux session's active pane. Nothing
found: `kein Claude im Hauptfenster`. Session file gone: `Sitzung beendet`.

### NEU and board size

NEU = newer than the timestamp of the owner's last prompt in that transcript. Board entries store
date and time (`2026-11-15 14:02`); the pane shows `14:02` for today and `15.11.` for older days.
Each section shows its newest entries that fit; the rest collapses into `+5 ältere`.

### Helpers

Only the main session writes the board; helpers report to it as usual. Owner ideas go only into the
main session (the hook skips calls that come from a helper).

### The board file

Path (decided by the owner):
- Normal case, one board per session: `~/.local/state/lage/<sessionId>.md`, outside every repo.
- Session started inside a sec lab folder (`~/src/sec/{re,ctf,live}/<name>/`): one board per lab
  folder, `<lab folder>/.claude/lage.md`, so a new session continues it and loot stays in the folder.
  Add `.claude/lage.md` to the sec `.gitignore` (it re-includes `live/.claude/`).

Created on first use. Claude learns the path from the hook (below) at session start, so the rule in
CLAUDE.md does not need to know session ids.

```
## Funde
- 14:02 ! Admin-Login ohne Sperre (/login), geprüft
- 13:50 Port 22 offen, OpenSSH 9.6
## Ungeprüft
- 14:05 UDP nicht gescannt (keine Zeit)
## Für dich
- 14:06 Ist 10.10.10.7 im Scope?
## Deine Ideen
- [ ] 14:10 Cookie anschauen
- [x] 13:40 robots.txt lesen → nichts drin
```

### How Claude keeps it

A short rule in `~/.claude/CLAUDE.md`: during work that finds things (security, debugging,
investigations), add one short simple-German line to `.claude/lage.md` for each finding, each thing
skipped, assumed or only guessed (this is how Claude's blind spots become visible to the owner), and
each thing the owner should check (this is how the owner's blind spots get pointed out). Tick owner
ideas `[x]` with a short result once handled. Never put loot secrets (passwords, hashes, keys) on
the board in full; name them (`SSH-Schlüssel gefunden → loot/`).

### How owner ideas reach Claude

A hook script `~/.claude/hooks/lage-ideas.sh` on `SessionStart`, `UserPromptSubmit` and
`PostToolUse`. At session start it tells Claude its board path. Afterwards, if the board has open
ideas Claude has not been shown yet, it prints them as added context
(`Neue Idee von vino: Cookie anschauen`). A small state file per session remembers what was shown,
so each idea is shown once.

### SITZUNGEN block

One line per file in `~/.claude/sessions/*.json` whose pid is alive: `name`, the topic (newest
`ai-title` entry of its transcript, short), and the state: `arbeitet`, `Helfer arbeiten`, or
`wartet: <first line of Claude's last message, cut>`. Sessions that wait for the owner come first,
marked `!`; the session in the master window is marked `▶`. At most about six lines.

### Cockpit change (`hypr-cockpit`)

If the work window runs Claude: open `kitty --class cockpit-log lage` on the right, also when other
windows are on the workspace (they stack below it). Otherwise behave exactly as today
(`journalctl -f` only when the workspace has one tiled slot). Toggle off closes it as today.

### pt dash change (sec repo)

One more pane: `lage --dir <folder>` when `lage` is on PATH, where `<folder>` is the lab folder
`pt dash` runs in (not the old `engagements/` path). With `--dir`, the view follows the newest
running Claude session whose start `cwd` lies inside that folder.

### Memory save stays out of live engagements

`memory-save.sh` skips every session whose start `cwd` or transcript `cwd` lies under
`~/src/sec/live/`. This fixes an existing leak and must ship before the first real engagement.

### Keys

`i` opens a one-line prompt `Idee:` and appends `- [ ] HH:MM <text>` under `## Deine Ideen`. The
pane never takes focus on its own; the owner clicks it or moves focus to it.

### Checks

- A script test with a fixture transcript and board (like `tools/memory-save.test.sh`): JETZT for a
  tool_use and an end_turn entry, NEU marking, idea append, the hook shows an idea exactly once.
- `hyprland --verify-config` / build as for the desktop work.
- Owner live checks: Super+C with Claude in the master shows the pane and follows a tab switch;
  `wartet auf dich` appears when Claude ends its turn; an idea typed in the pane shows up in
  Claude's next step; one practice CTF run with `pt dash`.

## Decided by the owner (2026-11-15)

- Approach B (Cockpit right pane), plus the same view in `pt dash`.
- The view helps on both sides: Claude's blind spots (Ungeprüft) and the owner's (Für dich), plus
  the owner's own ideas.
- One board per session; in a sec lab folder one per folder.
- A SITZUNGEN block at the bottom of the pane.

## Calls made by Claude (owner may overrule)

- Name `lage` for the program, German labels in the pane.
- Memory save skips live engagements (follows the existing live lab rule).
- Board entries store date and time; older ones collapse into `+N ältere`.
- NEU means "since your last message to this session", not "since you last looked at the pane".
- The pane opens only when the work window runs Claude; otherwise the Cockpit works as before.
- Owner ideas reach Claude through a hook, so they arrive even mid-turn.

## Left to the builder

- Bash + jq (house style) or a small Python script if bash grows past about 150 lines.
- Refresh by polling (about 2 s) or by file events.
- Whether each Hyprland kitty window has its own pid (`--single-instance` would break the pid walk;
  then use kitty's remote control or the window title instead).
- The exact project-folder name rule for transcripts (verify against `~/.claude/projects/`).
- Showing `wartet auf Erlaubnis` for a pending permission prompt, if cheap (e.g. a `Notification`
  hook writing a flag file); otherwise skip in v1.
- How the hook script is installed (home-manager file vs. a copy like `memory-save.sh`) and how the
  global git ignore is set.
