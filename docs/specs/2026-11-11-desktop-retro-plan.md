# Grey Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the laptop desktop into "Grey Console": one font (0xProto Nerd Font Mono), grey palette with teal focus, 2 px corners, a calm top bar plus a quiet-when-ok bottom bar, and a Cockpit layout on `Super+C`.

**Architecture:** Everything is Home Manager config in `modules/user/desktop/` plus the Stylix scheme and fonts in `themes/` and `lib/repository.nix`. Waybar gets a second bar; Hyprland gets master-layout options and one toggle script. No new flake inputs, no plugins.

**Tech Stack:** NixOS flake, Home Manager, Stylix (base16), Hyprland 0.56.2 native Lua config, Waybar, rofi, mako, kitty, bash + jq scripts.

**Spec:** `docs/specs/2026-11-11-desktop-retro-design.md` (read it first; this plan argues from it).

## Global Constraints

- Work in `~/src/bandit-nix-retro`, branch `feat/desktop-retro`. Never push; never touch `main`.
- Font: `pkgs.nerd-fonts._0xproto`, family `0xProto Nerd Font Mono`, size 18 everywhere. Only Regular, Bold, Italic exist.
- Palette: bg `#0d0d0e`, panel `#18181a`, inactive/separators `#303034`, dim text `#848488`, text `#d0d0d0`, focus teal `#00a99d` (base0C), warning `#fdb827`, critical `#ed4749`, privacy `#bc61bc`, ok `#61bb46`. Contrast of text and dim text ≥ 4.5:1 on bg and panel.
- Only base00–base07 change in the scheme. Focus consumers use base0C instead of base0D.
- Corner radius 2 px, borders 3 px, Hyprland `gaps_out = 6`, `gaps_in = 3`. Flat: no blur, shadows, gradients (except the one rainbow line).
- Only two glyphs stay in the bars: network and battery. Everything else is text.
- Keep every existing key binding; add only `Super+C`.
- Do not touch: wallpaper, hyprlock, the light specialisation, Thunderbird/Obsidian/Firefox config, `workstationTheme` in `lib/repository.nix` (legacy data the theme contract checks; it does not drive Stylix).
- Format changed Nix files with `nix fmt -- <files>`. No full `nix flake check` (earlyoom). Build with `--max-jobs 1`.
- Build command used below as `BUILD`: `nix build .#nixosConfigurations.bandit.config.system.build.toplevel --no-link --no-update-lock-file --max-jobs 1`
- Generated configs: `HM=.#nixosConfigurations.bandit.config.home-manager.users.vino.xdg.configFile`; files `"hypr/hyprland.lua"`, `"waybar/config"`, `"waybar/style.css"` (`nix build "$HM.\"waybar/config\".source" --no-link --print-out-paths`).

## Review Focus

1. A fullscreen window (Minecraft, `Super+F`) must cover both Waybars. Checked in Task 5 Step 5.
2. Six or more tabs in one group: titles stay readable and the active one is clearly teal. Checked in Task 5 Step 5.
3. A special or unnamed workspace (scratchpad, id > 9) still shows a sane label, not `{icon}` or an empty button. Checked in Task 3 Step 4.
4. The health line: old journal errors (> 15 min) must not keep it yellow; a slow or failing `journalctl` must not break the bar. Checked in Task 4 Step 2.
5. `Super+C` on an empty workspace, on a fullscreen window, and pressed twice: no error, and the second press returns to dwindle and closes only the log window Cockpit opened. Checked in Task 6 Step 4.

---

### Task 1: One font and the grey neutrals

**Files:**
- Modify: `lib/repository.nix:156-170` (Stylix `fonts`: monospace, sansSerif, serif)
- Modify: `themes/material-sand-dark.yaml` (scheme name and base00–base07)

**Interfaces:**
- Produces: `config.stylix.fonts.{monospace,sansSerif,serif}.name == "0xProto Nerd Font Mono"`; scheme base00 `0d0d0e`, base01 `18181a`, base02 `303034`, base03 `848488`, base04 `a8a8ac`, base05 `d0d0d0`, base06 `e4e4e6`, base07 `f4f4f5`, scheme name `"Grey Console"`. Accents base08–base0F unchanged.

- [ ] **Step 1: Check contrast of the new neutrals**

Run: `nix shell nixpkgs#python3 -c python3 -c 'L=lambda h:(lambda c:0.2126*c[0]+0.7152*c[1]+0.0722*c[2])([((v/255)/12.92 if v/255<=0.03928 else (((v/255)+0.055)/1.055)**2.4) for v in bytes.fromhex(h)]); r=lambda a,b:(max(L(a),L(b))+0.05)/(min(L(a),L(b))+0.05); print([round(r(f,b),2) for f in ("d0d0d0","a8a8ac","848488") for b in ("0d0d0e","18181a")])'`
Expected: all six numbers ≥ 4.5.

- [ ] **Step 2: Set all three Stylix font slots to `pkgs.nerd-fonts._0xproto` / `"0xProto Nerd Font Mono"` and write the new scheme values**

Keep the comment above `fonts` honest (one line: why 0xProto, why the Mono variant: one icon width everywhere).

- [ ] **Step 3: Verify**

Run: `nix eval --raw --no-update-lock-file .#nixosConfigurations.bandit.config.home-manager.users.vino.stylix.fonts.sansSerif.name`
Expected: `0xProto Nerd Font Mono`. Then `BUILD` succeeds and `nix build .#checks.x86_64-linux.theme-contract --no-link --no-update-lock-file` passes unchanged.

- [ ] **Step 4: Commit** `feat(desktop): 0xProto everywhere and Grey Console neutrals`

---

### Task 2: Hyprland, rofi, mako, GTK: teal focus, 2 px corners, 6 px gaps, master options

**Files:**
- Modify: `modules/user/desktop/hyprland/settings.nix:36-37` (gaps 3/6), `:47,82,110` (base0D → base0C), `:55-56` (snap gaps 6), `:62` (rounding 2), `:100-101` (groupbar rounding 2), groupbar `col.inactive` → base01, `text_color_inactive` stays base04; add a `master` block next to `dwindle`.
- Modify: `modules/user/desktop/rofi-wayland.nix:12` (`blue = colors.base0D` → rename to `focus = colors.base0C` and update its uses), radii at `:31,114,125,155,204` → `2px`.
- Modify: `modules/user/desktop/mako.nix:20` (`border-radius = 2`), `:28` (base0C).
- Modify: `modules/user/theme.nix:25,104,120,124,128,131` (base0C), `:91,113` (`2px`), and the comment at `:73-74`.
- Modify: `modules/user/desktop/hyprland/scripts.nix:16` (Flameshot `uiColor` base0C).

**Interfaces:**
- Produces: Hyprland option block `master = { mfact = 0.66; new_status = "slave"; orientation = "left"; }` (Task 6 relies on these; Cockpit only switches the layout name).

- [ ] **Step 1: Make the edits above.** The power menu in rofi stays red; mako critical stays a red border.

- [ ] **Step 2: Verify the generated Hyprland config**

Run: `Hyprland --verify-config -c "$(nix build "$HM.\"hypr/hyprland.lua\".source" --no-link --print-out-paths --no-update-lock-file)"`
Expected: no errors. Then `grep -c 'base0D\|009ddc' "$(…same path…)"` prints `0`.

- [ ] **Step 3: Verify rofi and the build**

Run: `BUILD`, then `rofi -dump-theme -theme <built rofi theme>` for both themes in `rofi-wayland.nix`. Expected: radius `2px`, selected row `#00a99d`.

- [ ] **Step 4: Commit** `feat(desktop): teal focus, 2 px corners, 6 px gaps`

---

### Task 3: Top bar: text workspaces, plain host, clean title

**Files:**
- Modify: `modules/user/desktop/waybar.nix:9-10` (`barFont` = `config.stylix.fonts.monospace.name`; delete the "proportional-icon" comment), `:117-118` (`modules-left = ["custom/host" "hyprland/workspaces"]`, `modules-center = ["clock"]`, `modules-right = ["hyprland/window"]`), `:126-129` (`custom/host` format = hostname only), `:136-173` (workspaces), `:176-180` (window title rewrite), CSS `:438-487` (host stripes removed; workspace styles).

**Interfaces:**
- Produces: `settings.mainBar` with only those modules; all other modules move to `settings.bottomBar` in Task 4.

- [ ] **Step 1: Workspaces as text.** `format = "{icon}"`; delete `format-window-separator`, `window-rewrite-default`, `window-rewrite`; `format-icons`: `"1" = "1 term"`, `"2" = "2 web"`, `"3" = "3 doc"`, `"4" = "4 game"`, `"5" = "5 code"`, `"6" = "6 chat"`, `"7" = "7 files"`, `"8" = "8 music"`, `"9" = "9 phone"`, `default = "+"`. Keep the dwm behaviour (only occupied + active) as configured today.

- [ ] **Step 2: CSS.** Buttons: no radius, dim text (base03), no fill. `button.active`: text base05, bold, and a 3 px rainbow line at the bottom drawn as `background-image: linear-gradient(to right, base0B 0 16.67%, base0A … base09 … base08 … base0E … base0D 83.33% 100%)` with `background-size: 100% 3px; background-position: bottom; background-repeat: no-repeat;`. `button.urgent`: text base08. Top bar: `window#waybar.top { border-bottom: 1px solid base02 }`. Host: no stripes, no glyph.

- [ ] **Step 3: Title.** `hyprland/window` gets `rewrite = { "^(◐|◓|◑|◒|✳|✶|✻|✽|✢|·|\\*) (.*)" = "$2"; }` (literal UTF-8 alternation: Waybar's std::regex works on bytes, so no `\x{…}` ranges). `max-length = 32` stays.

- [ ] **Step 4: Verify on screen**

Run the built bar for 5 s next to the live one: `timeout 5 waybar -c <built waybar/config> -s <built waybar/style.css> & sleep 3; grim -g "0,0 2256x48" /tmp/top.png`
Expected in the screenshot: `bandit │ 1 term │ …` in one font, rainbow line under the active workspace, no window icons, title without the spinner symbol. Also switch to a special workspace (`Super+grave` or the scratchpad bind in `bindings.nix`) and confirm the label is `+`.

- [ ] **Step 5: Commit** `feat(waybar): text workspaces and a quiet top bar`

---

### Task 4: Bottom bar with the health line and text modules

**Files:**
- Modify: `modules/user/desktop/waybar.nix`: `barLogs` (`:25-45`), new `barPrivacy` script next to it, new `settings.bottomBar`, module formats `:200-375`, CSS.

**Interfaces:**
- Consumes: `settings.mainBar` from Task 3.
- Produces: `settings.bottomBar = { layer = "top"; position = "bottom"; height = builtins.floor (barSize * 4 / 3 * 1.75); modules-left = ["group/admin"]; modules-right = ["custom/privacy" "network" "group/system" "pulseaudio" "bluetooth" "battery" "group/traydrawer"]; }`. `group/admin` stays as it is (the health line `custom/logs` is its visible handle; IPs and containers open on hover).

- [ ] **Step 1: Health rule in `barLogs`.** Output JSON `{text, tooltip, class}`:
  - failed units (system + user) > 0 → class `failed`, text `N FAILED · <first unit name>`;
  - else errors from `journalctl -p err --since -15min -q --no-pager -o cat | wc -l` > 0 → class `warn`, text `N ERR 15m`;
  - else class `ok`, text `all quiet`.
  Wrap each `journalctl`/`systemctl` call in `timeout 5`; on timeout treat the count as 0 and add `(journal timeout)` to the tooltip. Tooltip keeps today's content (failed list + last 5 errors). Click actions unchanged.

- [ ] **Step 2: Test the rule** (shell self-check in the plan, not shipped)

Run: `nix build` the script, then `"$out"/bin/waybar-logs | jq -r .class` → expect `ok` or `failed` matching `systemctl --failed`/`systemctl --user --failed`; then `logger -p user.err grey-console-test && "$out"/bin/waybar-logs | jq -r .text` → expect `… ERR 15m` (unless units failed). Expected after 15 min: no longer counts that error.

- [ ] **Step 3: `barPrivacy`.** `writeShellApplication` with `pkgs.pipewire pkgs.jq`; polls every 3 s: `pw-dump` → `MIC` if any node has `media.class == "Stream/Input/Audio"` and `state == "running"`; `SCREEN` if any node with `media.class == "Video/Source"` and `node.name` starting `xdph` is running. Text joins the active words, purple via class `active`; empty text hides the module. Remove the image-based `privacy` module.

- [ ] **Step 4: Text formats.** cpu `CPU {usage}%`, memory `MEM {percentage}%`, temperature `TEMP {temperatureC}°C`, disk `DISK {percentage_used}%`, power-profiles format-icons `perf`/`bal`/`save` with format `PWR {icon}`, pulseaudio `VOL {volume}%` / muted `VOL MUTE`, bluetooth `BT` / connected `BT ON` / with battery `BT {device_battery_percentage}%` / off `BT OFF`, containers `CTR {n}`, ip `LAN <ip> │ TS <ip>` (no glyphs), tray handle `<`. Network and battery keep their glyph. All normal values base04; only `.warning` base0A, `.critical`/`.failed` base08, `.warn` base0A, `custom-logs.ok` base03.

- [ ] **Step 5: CSS.** `window#waybar.bottom { border-top: 1px solid base02; }`; module separators stay `border-left: 1px solid base02`; drawer children on base01.

- [ ] **Step 6: Verify on screen**

Run both built bars 5 s and `grim -g "0,1462 2256x42" /tmp/bottom.png`. Expected: `all quiet` (or the real state) left, text modules right, one font, only the two glyphs, nothing clipped at 2256 px. Then `BUILD`.

- [ ] **Step 7: Commit** `feat(waybar): bottom bar with a quiet-when-ok health line`

---

### Task 5: Deploy and look at it live

**Files:** none (owner runs `sh ~/desktop-retro.sh`, which switches from this worktree).

- [ ] **Step 1:** `BUILD` once more from a clean tree (`git status` empty).
- [ ] **Step 2:** Owner runs `sh ~/desktop-retro.sh` on the laptop.
- [ ] **Step 3:** `fc-match "0xProto Nerd Font Mono"` → `0xProtoNerdFontMono-Regular.ttf`. `hyprctl layers` → two Waybar layers.
- [ ] **Step 4:** `notify-send -u critical test` → red border, normal text, 2 px corners.
- [ ] **Step 5 (Review Focus 1, 2):** Owner: Minecraft fullscreen covers both bars; a kitty group with 6 tabs is readable. Fix and re-commit before Task 6 if not.

---

### Task 6: Cockpit on `Super+C`

**Files:**
- Modify: `modules/user/desktop/hyprland/scripts.nix` (new `.local/bin/hypr-cockpit`)
- Modify: `modules/user/desktop/hyprland/bindings.nix:100` area (`execBinding "${mod} + c" "hypr-cockpit" "cockpit: master + log on/off"`)
- Modify: `modules/user/desktop/hyprland/rules.nix` (window rule for class `cockpit-log`: never auto-grouped, opens tiled)

**Interfaces:**
- Consumes: Task 2's `master` options.
- Produces: `hypr-cockpit` (no arguments, toggles the active workspace); state in `$XDG_RUNTIME_DIR/hypr-cockpit/<workspace id>`.

- [ ] **Step 1: Spike: can one workspace switch layout at runtime?** Live, on an empty test workspace with two kitties:
  `hyprctl eval 'hl.workspace_rule({ workspace = "<id>", layout = "master" })'` and watch whether the two windows re-tile at once (master left ≈ 2/3).
  - Re-tiles → per-workspace mode: on = add/enable the rule (keep its handle via `set_enabled`, or re-add with `layout = "dwindle"` for off).
  - Does not → global mode (spec allows it): `hyprctl keyword general:layout master|dwindle`.
  Write the result as one comment line at the top of the script.

- [ ] **Step 2: Implement `hypr-cockpit`.** On: switch the active workspace to master, then make the focused window (or its group) the master (`layout swapwithmaster master`); if the workspace has no other tiled window, start `kitty --class cockpit-log journalctl -f` (opens right, `new_status = "slave"`); write the state file. Off: switch back to dwindle, close windows with class `cockpit-log` on that workspace only (`hyprctl clients -j` + jq on `.workspace.id`), remove the state file. A fullscreen focused window or an empty workspace: do nothing and exit 0.

- [ ] **Step 3: Window rule** for `match.class = "^cockpit-log$"`: deny grouping (check the stub field name in `share/hypr/stubs/hl.meta.lua`, e.g. `group = "deny"`), tiled.

- [ ] **Step 4: Verify (Review Focus 5)**

Run `Hyprland --verify-config` on the built config, `BUILD`, owner switches, then live:
  - two windows, `Super+C` → `hyprctl clients -j | jq '[.[] | select(.workspace.id==<id>) | .at[0]]'` shows one window at x = 6 and one at x ≈ 1506;
  - one window, `Super+C` → a `cockpit-log` kitty appears right, not as a tab;
  - `Super+C` again → layout `dwindle`, the log kitty is gone, the other windows stay;
  - empty workspace and fullscreen window: `Super+C` changes nothing, no notification error.

- [ ] **Step 5: Commit** `feat(desktop): Cockpit layout on Super+C`

---

### Task 7: Hand-over

- [ ] Update `docs/specs/2026-11-11-desktop-retro-design.md` only where the build differed (e.g. global vs per-workspace Cockpit).
- [ ] Update the cheatsheet/keys menu if it lists binds by hand (`keybinds-menu.nix`), so `Super+C` shows up.
- [ ] Run `graphify update .` (AGENTS.md), commit, and tell the owner the merge step is theirs (signed commit, never via GitHub button).
