# Command palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Super+Space` opens a rofi command palette (one flat list, status line, live toggles) on the laptop.

**Architecture:** One bash script `tools/palette.sh` (testable with stub commands like `tools/waybar-*.sh`), wrapped by
`writeShellApplication` in a new Home Manager module `modules/user/desktop/palette.nix`, installed as
`~/.local/bin/palette` and bound in `hyprland/bindings.nix`. Target/VPN values come from the existing
`tools/waybar-target.sh` through a new `get` subcommand, so there is still one reader of the pt session file.

**Tech Stack:** bash, rofi 2.0 (`-dmenu`, row option `\0display\x1f<markup>`), jq, Home Manager, Hyprland Lua binds.

**Spec:** `docs/specs/2026-11-17-palette-design.md`

## Global Constraints

- Hosts build from `modules/` (Home Manager in `modules/user/`); `nixos/` and `home/` are dead.
- No full `nix flake check` (OOM on the laptop). Build: `nix build .#nixosConfigurations.bandit.config.system.build.toplevel --no-link --no-update-lock-file`.
- Commit unsigned in the worktree: `git -c commit.gpgsign=false commit …`; the owner signs and merges.
- Hyprland's PATH has no `~/.local/bin`: `palette.sh` appends it (`PATH=$PATH:$HOME/.local/bin`), so Nix runtime inputs win and `lage`, `waybar-stream`, `waybar-target`, `keybinds-menu`, `net-menu`, `powermenu`, `hypr-cockpit`, `hypr-screenshot`, `claude` resolve from there.
- Look: theme `retro-eighties`, prompt `befehl`, `-no-show-icons`, colours via env `PAL_DIM` (base03) and `PAL_WARN` (base0A).
- Labels exactly as in the spec table (German). Only the `target=` line of `~/src/sec/.pentest-session` is read (by `waybar-target`).
- The palette only shows and launches; no network/DNS action except opening `net-menu`.
- Rofi filters on the plain row text; colours go only into the `display` row option (verified on rofi 2.0: `-filter span` matches nothing, `-filter hack` matches the Hacken row, `-format i` gives the index).

## Review Focus

1. Stream mode on → no real IP in any row (plain or display) nor in `-mesg`; copying still copies the real value.
2. Esc in either rofi (exit 1, no output) → palette exits 0 and runs nothing.
3. A target like `a&b<c>` → display markup escaped (`&amp;`, `&lt;`, `&gt;`), palette still opens.
4. `lage` missing, failing, or no sessions → row `Claude: nichts offen`, no crash.
5. mako modes `dnd` and `stream` both active → `Ruhe: AN` (line match, not equality).

---

### Task 1: `waybar-target get` and install `waybar-target`

**Files:**
- Modify: `tools/waybar-target.sh` (new `get` branch after `target=` is computed, before the copy branch; usage line)
- Modify: `modules/user/desktop/waybar.nix` (one `home.file` line next to `.local/bin/waybar-stream`, ~line 679)
- Test: `tools/waybar.test.sh` (in the `# --- waybar-target` block, using `tg`)

**Interfaces:**
- Produces: `waybar-target get` → exactly two lines on stdout, line 1 = VPN IPv4 (or empty), line 2 = target (or empty), never masked, exit 0. Installed at `~/.local/bin/waybar-target`.

- [ ] **Step 1: Write the failing tests**

```bash
echo 'target=10.10.11.5' >"$t/ps"; [[ $(tg get) == $'10.10.14.7\n10.10.11.5' ]]
[[ $(STREAM=on tg get) == $'10.10.14.7\n10.10.11.5' ]]              # raw: the caller masks
rm "$t/ps"; [[ $(VPN=none tg get | wc -l) == 2 && -z $(VPN=none tg get | tr -d '\n') ]]  # both empty, still 2 lines
```

- [ ] **Step 2: Run** `tools/waybar.test.sh` → FAIL at the first `tg get` line.
- [ ] **Step 3: Implement** `get` in `tools/waybar-target.sh` (`printf '%s\n%s\n' "$vpn" "$target"; exit 0`) and add `home.file.".local/bin/waybar-target".source = "${barTarget}/bin/waybar-target";` with a one-line comment (used by the palette).
- [ ] **Step 4: Run** `tools/waybar.test.sh` → last line `ok`.
- [ ] **Step 5: Commit** — `feat(waybar): waybar-target get prints raw VPN and target for the palette`

### Task 2: `tools/palette.sh`

**Files:**
- Create: `tools/palette.sh`
- Test: `tools/palette.test.sh` (same shape as `tools/waybar.test.sh`: `set -euo pipefail`, temp dir, `stub`, stubs first on PATH, `HOME=$t/home`, final `echo ok`)

**Interfaces:**
- Consumes: `waybar-target get` (Task 1); `lage bar` (JSON, `.text` like `● 2 ▲ 2`); `waybar-stream status|toggle`; `makoctl mode` (one mode per line), `makoctl mode -t dnd`.
- Produces: `palette` (no args) for Task 3.

**Behaviour (from the spec):**
- Main rofi: `rofi -dmenu -i -markup-rows -format i -p befehl -theme retro-eighties -no-show-icons -theme-str 'listview { lines: 13; }' -mesg "<status>"`.
- Each row on stdin: `<plain>\0display\x1f<markup>`; plain = `printf '%-8s %s' group label` plus `  <value>` when there is a value or key hint; markup = same text with the group word and the value/hint in `<span color="$PAL_DIM">…</span>`, the label in `<span color="$PAL_WARN">` for `Claude wartet: N` (N > 0) and for `AN` in a switch row. Values are escaped (`&`, `<`, `>`) in markup.
- Rows in this order (hidden rows are left out, indexes follow the shown rows):

| plain row (filter text) | action |
| --- | --- |
| `KI       Claude wartet: N` / `KI       Claude: nichts offen` | `lage bar --focus` |
| `KI       Cockpit  Super+C` | `hypr-cockpit` |
| `KI       Claude in Ordner …` | folder list |
| `Hacken   Ziel-IP kopieren  <target or •••>` (only with target) | `waybar-target copy target` |
| `Hacken   VPN-IP kopieren  <vpn or •••>` (only with vpn) | `waybar-target copy vpn` |
| `Schalter Stream: AN` / `AUS` | `waybar-stream toggle` |
| `Schalter Ruhe: AN` / `AUS` | `makoctl mode -t dnd` |
| `Menüs    Programme  Super+D` | `rofi -show drun` |
| `Menüs    Tasten  Super+H` | `keybinds-menu` |
| `Menüs    Netz` | `net-menu` |
| `Menüs    Ablage  Super+Shift+V` | `cliphist list \| rofi -dmenu \| cliphist decode \| wl-copy` |
| `Menüs    Bildschirmfoto  Super+Shift+S` | `hypr-screenshot` |
| `Menüs    Aus / Sperren  Super+Esc` | `powermenu` |

- `-mesg`: parts joined by ` · `: `Claude wartet: N` (only N > 0), `Stream AN|AUS`, `Ziel <target or •••>` (only with target). Escaped like the rows.
- N = number after `▲ ` in `lage bar`'s `.text`; any failure → 0.
- Folder list: dirs `$HOME/src/*` whose `.git` is a directory (worktrees have a `.git` file), newest `.git` mtime first; second rofi `rofi -dmenu -i -format i -p ordner -theme retro-eighties -no-show-icons` with basenames; Enter → `exec kitty --directory <dir> claude`. None found → `notify-send Palette "Keine Ordner"`, exit 0.
- The action runs after rofi has returned (rofi already exited); Esc (rofi exit ≠ 0 or empty) → exit 0, nothing run.

**rofi stub (test):** saves stdin to `$t/rofi.<n>` and `"$*"` to `$t/rofi.<n>.args` (n = 1, 2, … per call); takes the n-th `|`-separated pattern from `$PICK`, prints the 0-based index of the first stdin row whose plain part (before `\0`) contains it, case-insensitive; no pattern or no match → exit 1. Every other stub (`lage`, `waybar-stream`, `waybar-target`, `makoctl`, `kitty`, `keybinds-menu`, `net-menu`, `powermenu`, `hypr-cockpit`, `hypr-screenshot`, `notify-send`, `cliphist`, `wl-copy`) appends `"<name> $*"` to `$t/log`, except the read-only queries `lage bar`, `waybar-stream status`, `waybar-target get` and `makoctl mode` (no flags); `lage bar` prints `{"text":"● 1 ▲ $WAIT"}` (`WAIT` default 2, `LAGE=fail` → exit 1); `waybar-target get` prints `VPN`/`TARGET` env (defaults `10.10.14.7`/`10.10.11.5`); `waybar-stream status` exits 0 when `STREAM=on`; `makoctl mode` prints `$MODES` (default `default`).

- [ ] **Step 1: Write the failing tests** (`pal() { bash "$here/palette.sh"; }`, `rows() { tr '\0' '\t' <"$t/rofi.1" | cut -f1; }`)

```bash
PICK=Stream pal; grep -qx 'waybar-stream toggle' "$t/log"
grep -q -- '-mesg Claude wartet: 2 · Stream AUS · Ziel 10.10.11.5' "$t/rofi.1.args"
[[ $(rows | wc -l) == 13 ]]; rows | head -1 | grep -q 'Claude wartet: 2'
PICK=Ruhe pal; grep -qx 'makoctl mode -t dnd' "$t/log"
MODES=$'default\ndnd\nstream' PICK=x pal || true; rows | grep -q 'Ruhe: AN'          # Review Focus 5
PICK=hack pal; grep -qx 'waybar-target copy target' "$t/log"
PICK='VPN-IP' pal; grep -qx 'waybar-target copy vpn' "$t/log"
PICK=Netz pal; grep -qx 'net-menu' "$t/log"
STREAM=on PICK=x pal || true; ! grep -q '10\.10\.' "$t/rofi.1" "$t/rofi.1.args"; grep -q '•••' "$t/rofi.1"  # Focus 1
TARGET='' VPN='' PICK=x pal || true; ! rows | grep -q Hacken; [[ $(rows | wc -l) == 11 ]]
TARGET='a&b<c>' PICK=x pal || true; grep -q 'a&amp;b&lt;c&gt;' "$t/rofi.1"                     # Focus 3
WAIT=0 PICK=x pal || true; rows | head -1 | grep -q 'Claude: nichts offen'
LAGE=fail PICK=x pal; rows | head -1 | grep -q 'Claude: nichts offen'                      # Focus 4
pal; [[ ! -s $t/log ]]                                                                           # Esc, Focus 2
# folders: $t/home/src/{old,new} with .git dirs, $t/home/src/wt with a .git file; touch old older
PICK='in Ordner|new' pal; grep -qx "kitty --directory $t/home/src/new claude" "$t/log"
[[ $(cat "$t/rofi.2") == $'new\nold' ]]                                                          # worktree skipped, newest first
PICK='in Ordner' pal; ! grep -q kitty "$t/log"                                                   # Esc in 2nd list
```

(Reset `$t/log` and `$t/rofi.*` before each `pal` in a small helper; exact helper shape is the implementer's.)

- [ ] **Step 2: Run** `tools/palette.test.sh` → FAIL (`palette.sh` missing).
- [ ] **Step 3: Implement** `tools/palette.sh` per the behaviour above (header comment like `tools/waybar-target.sh`: purpose, env, commands used).
- [ ] **Step 4: Run** `tools/palette.test.sh` → `ok`; `shellcheck tools/palette.sh tools/palette.test.sh` (via `nix shell nixpkgs#shellcheck` if missing) → clean.
- [ ] **Step 5: Commit** — `feat(palette): rofi command palette script with tests`

### Task 3: Nix module and key

**Files:**
- Create: `modules/user/desktop/palette.nix`
- Modify: `modules/user/desktop/default.nix` (import after `./keybinds-menu.nix`)
- Modify: `modules/user/desktop/hyprland/bindings.nix` (`systemBindings`, after the `${mod} + d` launcher line)

**Interfaces:**
- Consumes: `tools/palette.sh` (Task 2), `~/.local/bin/waybar-target` (Task 1).
- Produces: `~/.local/bin/palette`; bind `(execBinding "${mod} + SPACE" "~/.local/bin/palette" "command palette")`.

- [ ] **Step 1: Write** `palette.nix`: `pkgs.writeShellApplication { name = "palette"; runtimeInputs = [config.programs.rofi.package pkgs.jq pkgs.coreutils pkgs.findutils pkgs.gnused pkgs.mako pkgs.kitty pkgs.cliphist pkgs.wl-clipboard pkgs.libnotify]; text = "PAL_DIM='${colors.base03}' PAL_WARN='${colors.base0A}'\n" + builtins.readFile ../../../tools/palette.sh; }` (colors = `config.lib.stylix.colors.withHashtag`, as in `waybar.nix`), plus `home.file.".local/bin/palette".source = "${palette}/bin/palette";`.
- [ ] **Step 2: Add** the import and the bind.
- [ ] **Step 3: Build** `nix build .#nixosConfigurations.bandit.config.system.build.toplevel --no-link --no-update-lock-file` → succeeds (`writeShellApplication` runs shellcheck on `palette` and `waybar-target`).
- [ ] **Step 4: Check** `nix eval --raw .#nixosConfigurations.bandit.config.home-manager.users.vino.home.file.".local/bin/palette".source` prints a store path; `tools/palette.test.sh` and `tools/waybar.test.sh` → `ok`.
- [ ] **Step 5: Commit** — `feat(palette): Super+Space opens the command palette`

### Owner check after switching (not automated)

Super+Space opens fast; "str" + Enter flips stream mode on the bar and the palette then shows `•••`; Netz, Tasten, Aus / Sperren open from the palette; `Claude wartet` jumps to the waiting session; `Claude in Ordner …` → `bandit-nix` opens kitty with Claude there; group words and values look dim, `AN` yellow.
