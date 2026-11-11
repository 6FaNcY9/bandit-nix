# Desktop look "Graphite Six" (laptop bandit)

Date: 2026-11-11 · Branch: `feat/desktop-look` · Design: architect (Fable), built by Claude.

## Intent

The owner sits far from the screen, has dyslexia, and works as a white-hat
admin. He wants:

- one font and one size across the OS, big enough to read from a distance;
- the retro-Apple rainbow look, a little darker, with vibrant colours but
  not orange-heavy;
- a modern structure that fits cyber-sec nerds;
- privacy and open source as the identity. He dislikes Apple's closed
  system, not its retro rainbow look.

## Decisions

- **Palette** (`themes/material-sand-dark.yaml`, scheme "Graphite Six"):
  - cool near-black neutrals: base00 `0b0c0f`, base01 `14161b`, base02 `23262d`;
  - Apple-rainbow accents unchanged (tuned to 4.5:1 contrast);
  - base0F neutral grey.
- **Colour meaning:**

  | Colour | Meaning |
  | --- | --- |
  | blue 0D | focus / selection |
  | green 0B | ok |
  | yellow 0A | warning |
  | red 08 | critical |
  | purple 0E | privacy / locked |
  | teal 0C | network |
  | orange 09 | temperature / charging only |

  Body text is base05/base04, never an accent.
- **Rainbow as a signature** in three places only:
  - the six stripes on the Waybar host widget;
  - the wallpaper circuit;
  - hyprlock (still open, see the plan).
- **Font:** JetBrainsMono Nerd Font (Stylix), size 18 for apps, terminal,
  Waybar, rofi, mako, tooltips and the group bar. Chosen for its tall
  x-height, clear 0/O and 1/l/I, ligatures and Nerd icons.
- **Structure:**
  - flat, 8 px radius (controls 6–8 px), 3 px borders, no bevels, blur or shadows;
  - gaps 8 px everywhere (`gaps_in` 4, `gaps_out` 8);
  - inactive windows dimmed by 0.15.
- **Hyprland:**
  - solid blue active border, which reads better from a distance than the rainbow gradient;
  - filled group tabs: the active one blue with dark text;
  - Super+V / Super+B choose where the next tile opens (i3 split v/h);
  - Flameshot is no longer pinned (fullscreen leaked to the next window).
- **Waybar:**
  - top, full width, 2 px bottom line;
  - host with stripes, blue rounded active workspace, title of up to 32 characters, bold clock;
  - on the right: privacy, then logs (failed units, journal errors). IPs and containers open on hover. Then network, then CPU (memory, temperature, disk and power profile open on hover). Then volume, Bluetooth, battery and tray.
- **Rofi:** blue 3 px border, 8 px radius, selected row filled blue. The power menu stays red.
- **Mako:** 3 px border, 8 px radius. Critical: red border with normal text.
- **GTK:** flat controls with an 8 px radius and a blue focus. The Kvantum highlight is blue.
- **Bluetooth:** a click opens `bluetui` (TUI, floating). A right click opens the rofi quick menu. `blueman-applet` stays as the pairing agent.
- **Wallpaper:** `themes/free-net.svg` (onion-routing rings, rainbow circuit, blue padlock), rendered by resvg at build time.
- **Keyring:** `keyring-tpm-unlock` unlocks the GNOME keyring with a TPM-sealed password after a fingerprint login.

## Non-goals

- No changes to bindings (except Super+V/B), animations, secrets or the light specialisation.
- No change to Thunderbird or Obsidian.

## Plan

Each step has to pass its check before the next one.

**Done**

1. Palette. Check: build, `checks.theme-contract`.
2. Hyprland structure. Check: `Hyprland --verify-config -c <generated hyprland.lua>`.
3. Waybar. Check: run a 5 s test Waybar, screenshot it, and confirm nothing is clipped at 2256 px.
4. Rofi. Check: `rofi -dump-theme` on both themes.
5. GTK CSS. Check: build.
6. Mako. Check: build; on the live system, `notify-send -u low|normal|critical`.
7. Bluetooth TUI. Check: `bluetui` is in nixpkgs.

**Open (nice to have)**

8. hyprlock: blue 3 px outline, radius 8, six stripes above the input field.
9. Starship and kitty: no orange, active tab blue.
10. Wallpaper fine-tuning.

## Risks

- The owner may miss the rainbow window border. Reverting it is one line in `hyprland/settings.nix` (`active_border`).
- `ci/theme-contract.nix` now asserts radius 8 (it was 0).
- `nix flake check` repository lints (statix) also fail on main: `hosts/bandit-lab/services/memory/default.nix`, `monitoring/dashboards.nix`, `modules/desktop/desktop.nix`.
