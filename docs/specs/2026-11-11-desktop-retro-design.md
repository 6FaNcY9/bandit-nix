# Desktop look "Grey Console" (laptop bandit)

Date: 2026-11-11 · Branch: `feat/desktop-retro` (on top of the local
`integrate/2026-11-11-evening`, which is what the laptop runs) ·
Design: architect (Fable), mockups shown to the owner in the brainstorming
browser tab (`.superpowers/brainstorm/`, ignored by git).

Replaces the look of [Graphite Six](2026-11-11-desktop-look-design.md);
everything that document decided and this one does not touch stays.

## Intent

The owner is a white-hat cyber-security network admin with dyslexia and
ADHD who sits far from the screen. After Graphite Six he said:

- the fonts do not match, especially the glyphs in Waybar and in the
  window tab bar;
- he wants a more retro, nerdy look: greyer, darker, square-ish corners;
- too many glyphs, too little ASCII: text labels and line structure, plus a
  few glyphs;
- dwm/i3-style tiling, but "we don't have to copy their structure".

Success: one font size and one icon size everywhere; he can tell at a glance
where he is (workspace, session) and whether something is wrong, without
reading a wall of icons.

## Goals

1. One font family and one Nerd Font variant (the Mono one) for every surface.
2. The "Grey Console" palette and 2 px corners.
3. Layout "Deck" as the normal state, with a "Cockpit" mode on one key.
4. Text labels instead of glyphs; only the network and battery glyphs stay.

## Non-goals

- No hy3 plugin, no Sway, no niri/scrolling layout.
- No i3 "stacked" group display, no nested containers.
- No changes to the wallpaper, hyprlock, the light specialisation,
  Thunderbird, Obsidian or Firefox.
- No changes to existing key bindings, except the one new Cockpit key.

## Anti-goals (a failure even if it works)

- Icons of different sizes, or a font fallback showing in the bars.
- Windows that jump or reflow on their own (the Cockpit only changes on the
  owner's key press).
- Orange-heavy colours; rainbow anywhere except the one line below.
- A fullscreen game (Minecraft) that no longer covers both bars.

## Root cause of the glyph mismatch (checked by the architect)

- `lib/repository.nix:156-166`: monospace is `JetBrainsMono Nerd Font Mono`
  (icons one cell), sansSerif/serif are `JetBrainsMono Nerd Font`
  (icons about two cells). Waybar, rofi and mako use sansSerif; the Hyprland
  group bar uses monospace.
- `modules/user/desktop/waybar.nix:139`: window icons shrunk to 66.667 %.
- Privacy and tray modules draw icon-theme images, not font glyphs.
- Window titles contain symbols the font lacks (e.g. `◐`), so fontconfig
  falls back to another font.

Fix: every Stylix font slot names the same Mono variant; drop the 66 % span
and the per-window icons.

## Decisions

### Font

**0xProto** (owner's pick from about 25 Nerd Fonts shown at size 18):
`pkgs.nerd-fonts._0xproto`, family `0xProto Nerd Font Mono`. All Stylix
slots (monospace, sansSerif, serif) use this one family, Mono variant,
size 18 as now. It ships Regular, Bold and Italic only, so nothing may ask
for Medium/SemiBold (bold clock = Bold). `ci/theme-contract.nix:31` asserts
the font name and changes with it; the wallpaper render
(`lib/repository.nix` resvg `--use-fonts-dir` JetBrains) is left alone.
Thunderbird and Firefox read the sansSerif/serif slots; they show JetBrains
Mono today and will show 0xProto. That is intended.

### Palette "Grey Console"

Written into the Stylix scheme (`themes/material-sand-dark.yaml`, keep the
file name, rename the scheme to "Grey Console"):

| Role | Hex |
| --- | --- |
| background | `#0d0d0e` |
| panel / bars | `#18181a` |
| inactive border, separators | `#303034` |
| dim text | `#848488` (was #808084; raised for 4.5:1 on the panel) |
| text | `#d0d0d0` |
| focus / active (replaces blue) | `#00a99d` teal |
| warning | `#fdb827` |
| critical | `#ed4749` |
| privacy / locked | `#bc61bc` |
| ok | `#61bb46` |

Colour meaning from Graphite Six stays (green ok, yellow warning, red
critical, purple privacy); only the focus colour moves from blue to teal.
Contrast of text and dim text on both backgrounds must stay at least 4.5:1.

Base16 slots (my call): only the neutrals base00–base05 change. The accent
slots keep their values, so base0D stays blue for terminal, nvim and the
rainbow line, and base0C is already `#00a99d`. Every focus consumer
(Hyprland borders and groupbar, rofi, mako, GTK/Kvantum highlight, Waybar)
is repointed from base0D to base0C. base09 (orange) and base0F stay; the
rainbow line keeps all six colours since it is one thin line.

### Shape

- Corner radius 2 px everywhere: windows, group tabs, rofi, mako, GTK
  (`lib/repository.nix:94`, `rofi-wayland.nix:31,114,125,155`,
  `mako.nix:20`, `ci/theme-contract.nix:28` asserts 8 today).
- Borders 3 px. Active border solid teal, inactive `#303034`.
- Gaps: 6 px to the screen edge and 6 px between windows
  (builder's call: Hyprland `gaps_out = 6`, `gaps_in = 3`).
- Flat: no blur, no shadows, no gradients (as now).

### Layout "Deck" (normal state)

At 2256x1504, scale 1:

- **Top bar**, 48 px:
  - left: `bandit │ 1 term │ 2 web │ …` — host name as text (no NixOS glyph),
    then workspaces as `N name`, only occupied ones plus the active one
    (dwm style); the special (scratchpad) workspace stays hidden, workspaces
    above 9 show `+`. Active one in text colour with a 3 px six-colour rainbow
    line under it; others dim. No window icons.
  - centre: clock `WED 11 · 19:18`, bold.
  - right: title of the focused window, at most 32 characters. Waybar
    rewrites away symbols the font lacks (e.g. Claude Code's `◐` spinner).
- **Group tab bar** (Hyprland groupbar), 38 px, full window width: active tab
  filled teal with dark text, others dim on panel colour, 2 px radius.
  With many tabs the titles get shortened (builder's call how). Groups stay
  on demand (`Super+S`, as today), only restyled; single windows get no tab
  bar (my call: no new auto-group rules, nothing jumps). The groupbar cannot
  rewrite titles, so a missing symbol there may still fall back (accepted).
- **Window area** below, full width.
- **Bottom bar**, 42 px, new second Waybar:
  - left: the health line, built from today's `group/admin` logs counter.
    Rule (my call): failed units (system + user) show always, in red
    `2 FAILED · sshd.service`; journal errors (`-p err`) count only from the
    last 15 minutes, in yellow `3 ERR 15m`. Neither: `all quiet` in dim text.
    Click keeps today's action (open the log view).
  - right, all text: privacy as purple text `MIC` / `SCREEN`, only while
    in use (replaces the image-based privacy module; `waybar-privacy` polls
    `pw-dump`: MIC = running `Stream/Input/Audio` node, which also fires for
    level meters such as pavucontrol; SCREEN = running `Video/Source` node
    named `xdph*`, not yet seen on a real share), network
    (glyph + `↓35.7k ↑13.1k`), `CPU 19%`, `VOL 10%`, `BT`, battery
    (glyph + `80%`), tray drawer. The existing hover drawers (IPs/containers,
    memory/temperature/disk/power) stay, with text labels.
  - Normal values in dim text; only warning/critical states get colour.

Workspace names (builder keeps the existing 1–9 categories from
`waybar.nix:142-152`, lower case because mixed/lower case reads easier with
dyslexia — my call): `1 term`, `2 web`, `3 doc`, `4 game`, `5 code`,
`6 chat`, `7 files`, `8 music`, `9 phone`.

### Mode "Cockpit" (on demand)

- **Key:** `Super+C` toggles Cockpit on the current workspace (builder:
  confirm `Super+C` is free in all Hyprland binding files; today
  `bindings.nix` binds a b d e f g h j k l m p r s v).
- **What it shows:** Hyprland master layout. The focused window or tab
  group is the master, about two thirds of the width (`mfact` ≈ 0.66,
  matches the mockup 1494 px + 744 px). The other windows of the workspace
  stack on the right. If the workspace has no other window, the toggle opens
  a kitty with `journalctl -f` on the right.
- **Toggle off:** back to dwindle; the log kitty that Cockpit opened closes.
- **As built:** Hyprland 0.56.2 switches one workspace at runtime
  (`hl.workspace_rule` via `hyprctl eval`, back to `dwindle` on toggle off), so
  no global toggle. The focused window is made master with
  `swapwithmaster ignoremaster`. The log kitty has `no_initial_focus` and
  `group = "deny"`, so focus stays on the work window and the log is never
  swapped into master. Script: `~/.local/bin/hypr-cockpit`
  (`modules/user/desktop/hyprland/scripts.nix`); state in
  `$XDG_RUNTIME_DIR/hypr-cockpit/<workspace id>`.

### Rofi, mako, GTK, Kvantum

Same palette and radius; focus colour teal instead of blue. The power menu
stays red. Mako critical stays a red border with normal text.

## Constraints

- Hyprland 0.56.2, native Lua config (`modules/user/desktop/hyprland/`);
  keep `package = null` / `portalPackage = null`.
- Stylix owns colours and fonts; hand-written Hyprland/rofi/mako settings
  must not conflict with generated ones (AGENTS.md).
- Full `nix flake check` gets killed by earlyoom on the laptop: build the
  laptop system and run the targeted checks only; build with
  `--max-jobs 1` while other sessions run.
- The owner deploys with one short script command (`sh ~/desktop-retro.sh`).

## Checks

- `Hyprland --verify-config` on the generated `hyprland.lua`.
- `checks.theme-contract` with the new radius and font.
- Run both Waybars for 5 s, screenshot at 2256 px: nothing clipped, one icon
  size, no fallback glyphs.
- `fc-match` for the chosen family resolves to the Nerd Font Mono file.
- Live (owner): Cockpit on/off twice; Minecraft fullscreen covers both bars;
  `notify-send -u critical` looks right.

## Left to the builder

Exact CSS, the scheme's base06/07 and base10+ values, how tab titles get
shortened, the log kitty's class/rule, and the order of work.
