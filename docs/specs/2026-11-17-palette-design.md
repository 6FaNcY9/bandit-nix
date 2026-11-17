# Command palette (rice part 2 of 4)

Date: 2026-11-17. Branch `feat/palette` (worktree `~/src/bandit-nix-palette`), base origin/main e9ec306.
Size: small change (one new script + module + one key).

## Why

Part 1 (bar) shows state. Part 2 is the one place to act: the owner presses one key, types a few letters and runs a
command, instead of remembering seven separate keys and menus. It must also toggle stream mode (`waybar-stream toggle`).
The owner handed over both the what and the how ("mach wie du recommendest"); entries and layout are Claude's call,
drafted with the architect. The owner picked look **A** (one flat list) from browser mockups.

## Goals

1. `Super+Space` opens a rofi palette in the existing `retro-eighties` look (font 16, teal focus).
2. One flat list, fuzzy and case-insensitive; Enter runs and closes, Esc closes.
3. Each row: dim group word (8-char column) + label + optional dim value or key hint on the right. Typing a group word
   ("hack") filters to that group.
4. A status line on top (`-mesg`): `Claude wartet: 2 · Stream AUS · Ziel 10.10.11.5`; empty parts are left out.

## Entries

| Group | Label | Action |
| --- | --- | --- |
| KI | `Claude wartet: N` (yellow when N > 0) / `Claude: nichts offen` | `lage bar --focus` |
| KI | `Cockpit` · `Super+C` | `hypr-cockpit` |
| KI | `Claude in Ordner …` | second list (below) |
| Hacken | `Ziel-IP kopieren` · value | `waybar-target copy target` (row hidden without target) |
| Hacken | `VPN-IP kopieren` · value | `waybar-target copy vpn` (row hidden without tun* IPv4) |
| Schalter | `Stream: AN/AUS` (AN yellow) | `waybar-stream toggle` |
| Schalter | `Ruhe: AN/AUS` | `makoctl mode -t dnd` |
| Menüs | `Programme` · `Super+D` | `rofi -show drun` |
| Menüs | `Tasten` · `Super+H` | `keybinds-menu` |
| Menüs | `Netz` | `net-menu` |
| Menüs | `Ablage` · `Super+Shift+V` | the cliphist picker of `bindings.nix` |
| Menüs | `Bildschirmfoto` · `Super+Shift+S` | `hypr-screenshot` |
| Menüs | `Aus / Sperren` · `Super+Esc` | `powermenu` |

**Claude in Ordner …** opens a second rofi list of main checkouts in `~/src` (`.git` is a directory, so the many
worktrees with a `.git` file stay out; 7 today), newest first; Enter opens `kitty --directory <dir> claude`.

State sources (all already exist, no new readers): `lage bar` JSON (`▲ N` = waiting, ~50 ms), `waybar-stream status`,
`makoctl mode` (line `dnd`, grep by line), `tools/waybar-target.sh` logic for target/VPN.

## Approaches

| | Approach | Trade-off |
|---|---|---|
| **A (picked)** | One flat `rofi -dmenu` list with group column and status line | Everything in one view and one search; 13-14 rows is near the limit for a quick read, the group column carries scanning |
| B | Two levels (group, then command) | Calmer first screen, but every command costs an extra step and search stays inside one group |
| C | Like A, toggles keep the palette open and flip ✓/✗ in place | Direct feedback, but reopen flicker, a loop, glyphs over words; can be added later |

Rejected outright: a new launcher (walker, anyrun, fuzzel) or rofi script mode; `-dmenu` matches every other menu here.

## Rules

- Stream mode on → IP values in rows and status line show `•••`; copying still copies the real value (the
  notification of `waybar-target copy` is already masked).
- The palette only shows and launches. No network/DNS action other than opening `net-menu`.
- Only the `target=` line of `~/src/sec/.pentest-session` is read.
- The chosen command runs after rofi has exited, so menus that use rofi themselves can open.
- Rows are a plain `group|label|value|command` table in the script, so parts 3 (layouts) and 4 (looks) later only add rows.

## Non-goals

No history/frecency, no per-session Claude list, no entries for parts 3-4 yet, no new rofi theme.

## Anti-goals

- An IP visible in the palette while stream mode is on.
- Opening feels slow (target well under 300 ms).
- A child menu (Netz, Tasten, Power …) fails to open because the palette's rofi is still running.

## Build shape

- Script `tools/palette.sh` (testable like `tools/waybar-*.sh`), wrapped by `writeShellApplication` in a new
  `modules/user/desktop/palette.nix`, installed as `~/.local/bin/palette`; reuse `tools/waybar-target.sh` for copying.
- Bind `${mod} + SPACE` in `hyprland/bindings.nix` (free today) with description "command palette".

## Verification

- `tools/palette.test.sh` with stubs (rofi, lage, makoctl, waybar-stream, ip): rows hidden without IPs, `•••` in stream
  mode, each row runs its command, the folder list skips worktrees, names with `&`/`<` do not break markup.
- Targeted laptop build (no full `nix flake check`, it is OOM-killed).
- Owner live test: Super+Space opens fast, "str" + Enter flips stream mode on the bar, Netz/Tasten/Power open from the
  palette, "Claude wartet" jumps to the waiting session.

## Left to the builder

- Settled during planning: rofi 2.0 filters on the plain row text when the colours go into the `\0display\x1f<markup>`
  row option (with plain `-markup-rows` rows it matched the markup itself).
- Line count via `-theme-str` so 13-14 rows fit at font 16.
