# Bar: AI, agents, target, stream mode (rice part 1 of 4)

Date: 2026-11-17. Branch `feat/bar-ai` (worktree `~/src/bandit-nix-bar`), base origin/main 04234e9.

## Why

The owner wants the laptop rice to feel like a modern hacker/dev setup built around AI, and asked for a smaller font.
After seeing ideas from public setups (Omarchy, agent status bars, CTF/HTB bars, red-team opsec kits) they picked all
eight; this is part 1, the bar. Parts 2-4 (command palette, work layouts, look switch) are separate designs.

The bar is what the owner looks at all day. It should answer three questions at a glance: are my Claude sessions busy
or waiting for me, how much of the weekly Claude limit is left, and (while hacking) what is my VPN IP and target.
When the screen is shared, it must not leak IPs or the hostname.

## Goals

1. Font 16 instead of 18 everywhere Stylix reaches (bar, kitty, GTK, rofi, mako, hyprexpo).
2. Top bar right: agents (`● 2 ▲ 1` = 2 busy, 1 waiting for the owner) and weekly limit (`AI ▰▰▰▰▰▰▱▱▱▱ 68%`).
3. Bottom bar left, after the health line: hacking target (`󰖂 10.10.14.7 → 󰓾 10.10.11.5`), only while a VPN or a target exists.
4. Stream mode: while a screen share runs (or toggled by hand), IPs and hostname show as `•••` and notifications are silent.

## Non-goals

- No new bar program (Quickshell, eww, ags). Waybar stays.
- No masking of the built-in `network` module tooltip (hover only; Waybar cannot change it at runtime).
- No usage tracking beyond what Claude Code already passes to the statusline (no ccusage, no API calls).
- Parts 2-4 of the rice.

## Anti-goals (fails even if it "works")

- The agent count in the bar differs from what the LAGE pane says.
- Either bar overflows or clips at 2256 px with font 16.
- Stream mode keeps showing an IP or the hostname for more than one privacy poll (3 s) after a share starts.
- New polling that costs noticeable CPU (no heavy command every second; each module run well under 200 ms).
- Credentials or tokens read or copied anywhere.

## Constraints

- Hosts build from `modules/` (Home Manager in `modules/user/`); `nixos/` and `home/` are dead.
- One look: Grey Console palette (`themes/material-sand-dark.yaml`), teal base0C = focus/ok, yellow base0A = warn,
  red base08 = critical, grey base03 = stale/dim. Text over glyphs where possible; Nerd Font glyphs allowed for VPN/target.
- `~/.claude/sessions/<pid>.json` is an undocumented Claude Code format; lage already depends on it. Keep that
  dependency in one place (lage).
- Full `nix flake check` is OOM-killed on the laptop; run targeted builds/tests.
- Agents commit unsigned in the worktree; the owner tests, signs and merges.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| **A (picked)** | Small custom modules in the existing `waybar.nix`; agent count comes from a new `lage bar` subcommand | Reuses lage's session logic, so bar and pane always agree; matches how `custom/ip`, `custom/logs` are built |
| B | All modules as standalone scripts; agents counted straight from `~/.claude/sessions/*.json` | Simpler, but `idle` sessions count differently from lage (lage treats idle as waiting unless helpers run), and the undocumented format gets a second reader |
| C | Replace Waybar with Quickshell/eww for richer widgets | Large rewrite, throws away the tuned bars, out of proportion for four modules |

The owner handed over the how ("mach wie du es empfiehlst"); A is Claude's call.
Placement: the owner chose **A2** from mockups (agents + AI on top, target bottom-left) so both bars stay balanced.

## Design

### 1. Font 16

`lib/repository.nix` `mkStylixTheme` → `fonts.sizes.{terminal,applications,desktop,popups} = 16`; update the comment
(18 was chosen to fit the bar; 16 frees room for the new modules). Callers are only the desktop module
(`modules/desktop/theme.nix`) and the standalone `homeConfigurations.vino` (`flake.nix:91`), so only the laptop
changes. Everything else follows Stylix (bar CSS
`font-size: ${barSize}pt`, kitty, GTK, rofi, mako, hyprexpo text). Thunderbird's own `font.size 14` stays.

### 2. Top bar

`modules-right = ["custom/agents" "custom/ai"]` — `hyprland/window` is removed (also good for stream mode: no window
titles on the bar).

**`custom/agents`** — `exec = lage bar`, `return-type = json`, `interval = 5`.
- New subcommand `lage bar` in `tools/lage.py` prints one Waybar JSON line and exits.
- Counts live sessions (pid alive in `/proc`) with the same classification `jetzt()` uses for the pane
  (`tools/lage.py:344-367`, states `tool`, `denkt`, `wartet`, `helfer`): `tool`, `denkt` and `helfer` → busy `●` (teal),
  `wartet` (incl. lage's idle-means-waiting rule) → waiting `▲` (yellow). *Claude's call: a session whose helpers still
  run is working, not waiting for the owner.*
- Text `● 2 ▲ 1`; a zero part is left out; no live session → empty text (module hidden).
- `class`: `waiting` when any session waits (yellow), else `busy`.
- Tooltip: one line per session, `▲ <short cwd> · seit 3 min` / `● <short cwd>`.
- Left click: `lage bar --focus` focuses the longest-waiting session's window (none waiting → the longest-busy one).
  Matching goes **downward**, like `lage --probe` (`claude_session_under()`, `tools/lage.py:180-210`): for each
  `hyprctl clients -j` pid, probe its process tree for the target claude pid (this also covers tmux client → pane).
  Focus with the repo's dispatch syntax `hl.dsp.focus({ window = "address:…" })` (`hyprland/scripts.nix:80,95`).
  Grouped kitty tabs must end up as the active tab.
- Must stay cheap: `Transcript.update()` reads from position 0 today (`tools/lage.py:253-269`). `lage bar` gets a
  tail-seek (read only the last part of each transcript) plus a test that a tail read classifies exactly like a full
  read (`settled`, `helpers()`).

**`custom/ai`** — reads the claude-hud usage snapshot, `interval = 30`.
- One-time owner-home config (not Nix-managed, plain file): `mkdir -p ~/.cache/claude-hud` (claude-hud only writes
  into an existing directory; a Home Manager `home.file`/activation line may create it), then set
  `display.externalUsageWritePath = "/home/vino/.cache/claude-hud/usage.json"` in `~/.claude/plugins/claude-hud/config.json`.
  claude-hud then writes `{updated_at, five_hour:{used_percentage,resets_at}, seven_day:{…}}` (0600, atomic) whenever a
  session renders the statusline.
- Text: `AI ▰▰▰▰▰▰▱▱▱▱ 68%` from `seven_day.used_percentage` (10 cells).
- `class`: `ok` (teal) < 80 %, `warn` (yellow) ≥ 80 %, `crit` (red) ≥ 95 %, `stale` (grey) when `updated_at` is older than
  10 min. File missing or unreadable → empty text (hidden).
- Tooltip: `Woche 68 % · reset in 3d 4h` and `5 h 12 % · reset in 2h 10m`.

### 3. Bottom bar: `custom/target`

`modules-left = ["group/admin" "custom/target"]`, `interval = 5`.
- VPN IP: first IPv4 of any `tun*` device (`ip -4 -j addr`); the owner's THM/HTB configs use `dev tun`.
- Target: `target=` line of `~/src/sec/.pentest-session` (the `pt` default: `PENTEST_DIR` = sec repo root, see
  `~/src/sec/nix/pt-entry.sh:12`). Put the path in one Nix let-binding.
- Text `󰖂 <vpn> → 󰓾 <target>` (VPN green base0B, target red base08); a missing part is left out with its arrow; both
  missing → hidden.
- Left click copies the target IP, right click the VPN IP (`wl-copy`, as `custom/ip` does).

### 4. Stream mode

- Flags in `$XDG_RUNTIME_DIR`: `bar-stream-auto` (set by the privacy loop) and `bar-stream-manual` (set by hand).
  Stream mode is on while either exists.
- Notifications: a new mako mode `stream` (`"mode=stream" = { invisible = 1; }` in `mako.nix`), separate from the
  owner's `dnd` (Mod+Shift+D, `bindings.nix:119`), so a share ending never clears a DND set by hand and Mod+Shift+D
  during a share does not unmute. *Claude's call.*
- `waybar-privacy`: on the transition to SCREEN it creates `bar-stream-auto`, runs `makoctl mode -a stream` and signals
  the bar; on the transition away it removes the flag and runs `makoctl mode -r stream` only if no manual flag is set.
- Manual toggle: a free Hyprland key (builder picks it, listed in `keybinds-menu`) toggles `bar-stream-manual` + mode
  `stream` and signals the bar. Part 2 (palette) will expose the same toggle later.
- Masked modules re-render at once via `signal` (`pkill -RTMIN+<n> waybar`): `custom/host` becomes an exec module
  (hostname or `•••`), `custom/ip` and `custom/target` print `•••` and drop IPs from their tooltips.
- While on, `custom/privacy` shows `SCREEN` plus a marker that the bar is masked (e.g. `SCREEN ●`).
- Known limit: up to 3 s (one poll) before an automatic share is detected. The built-in `network` tooltip is not
  masked.

## Verification

- `tools/lage.test.sh` gains cases for `lage bar` (busy/waiting/idle-with-helpers/no sessions → JSON text and class).
- Small self-checks for the new shell modules (fixture `.pentest-session`, fake usage JSON incl. stale and missing).
- Targeted build: `nix build .#nixosConfigurations.bandit.config.system.build.toplevel` (no full flake check).
- Owner on the laptop after switching the branch: both bars fit at 16, the `▲` sessions are the ones the LAGE pane
  lists as waiting (the pane shows no busy count, so only `▲` can be compared), click
  jumps to the waiting session, AI shows the same % as the Claude statusline, `pt` target appears/disappears, screen
  share in a browser masks IPs and silences notifications, manual key toggles it.

## Left to the builder

- Exact free key for the manual stream toggle.
- Exact signal number(s) and CSS for the new classes (use existing palette tokens).
- How `lage bar --focus` selects a tab inside a kitty group if `focuswindow` alone does not.
- Whether `custom/target` and `custom/ip` share one helper script.
