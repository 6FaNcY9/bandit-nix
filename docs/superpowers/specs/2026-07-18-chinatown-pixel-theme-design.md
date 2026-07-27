# Chinatown Pixel System Theme Design

> Approved design for the `bandit` laptop. Waybar is the status bar. The
> `bandit-lab` server and dormant i3/Polybar/Dunst configuration are out of
> scope.

## Objective

Refactor the active laptop theme into one coherent system named **Chinatown
Pixel**, derived directly from the current pixel-art Chinatown wallpaper. Every
visible surface should share the wallpaper's dark architectural base, warm
coral lighting, slate-blue shadows, hard pixel edges, and restrained depth.

The result must feel intentionally designed as one system while remaining
readable, maintainable through Nix, and practical for daily use.

## Scope

The refactor covers the active `bandit` laptop experience:

- boot, console, Plymouth, and greetd/greeter surfaces;
- Hyprland borders, gaps, groups, and compositor effects;
- Waybar, including modules, states, tooltips, and tray treatment;
- Rofi launcher and session controls;
- Mako notifications;
- GTK 3/4 and Qt/Kvantum applications;
- PCManFM and native file/dialog surfaces inherited from GTK/Qt;
- Firefox browser chrome, without restyling website content;
- Thunderbird chrome and mail-list surfaces;
- Kitty, Fish, Starship, and shell-adjacent tools;
- Neovim and plugin chrome;
- Git/delta, bat, fzf, btop, and other supported terminal tools;
- system fonts, prominent icons, and cursor treatment.

The following are explicitly excluded:

- `bandit-lab` and its server palette;
- dormant i3, Polybar, and Dunst modules;
- website content inside Firefox;
- application-specific themes that cannot be declared reproducibly;
- animated, translucent, or blurred effects added solely for decoration.

## Visual Language

### Palette

The wallpaper is the visual source of truth. Its colors are encoded in a new
Base16 scheme and exposed through semantic Nix tokens. The core semantic roles
are:

| Role | Color | Purpose |
|---|---|---|
| Canvas | `#101915` | Desktop-adjacent backgrounds and deepest recesses |
| Primary surface | `#1B2525` | Bars, menus, panels, and application chrome |
| Raised surface | `#323B47` | Selected containers and raised controls |
| Structural olive | `#3B413B` | Dividers and muted architectural detail |
| Shadow blue | `#53556B` | Secondary outlines and pixel-offset depth |
| Foreground | `#F3AB8B` | Primary text and strong focus treatment |
| Muted foreground | `#DB9673` | Secondary labels and inactive text |
| Primary coral | `#E96B59` | Selection, focus, and primary actions |
| Active orange | `#D86531` | Active workspaces and emphasized status |
| Secondary rose | `#D37887` | Alternate informational emphasis |
| Critical red | `#A4322E` | Destructive, urgent, and critical states |

The Base16 file may include additional wallpaper colors needed by terminal and
syntax themes, but all application adapters consume named semantic roles rather
than embedding hexadecimal literals. Fixed black or white may be used only
where an upstream format requires it and the exception is documented beside
the value.

### Geometry and spacing

- Use a 4 px spacing grid for outer gaps, module padding, and control spacing.
- Use square corners everywhere; the intended radius is `0`.
- Use 1 px dividers, 2 px focus outlines, and at most 3 px structural borders.
- Use a selective 1 px offset edge or inset bevel when separation is needed.
- Do not use blur, gradients, glass effects, soft drop shadows, or decorative
  transparency.
- Disable nonessential transitions and motion. State changes should be
  immediate.

### Typography

Use a hybrid typography system:

- a packaged bitmap/pixel font for Waybar, Rofi, Mako, greeter labels, and
  other short desktop-shell labels;
- Iosevka Term Nerd Font Mono for Kitty, Neovim, code, and dense technical
  readouts;
- Noto Sans, Noto CJK Sans, and Noto Color Emoji as coverage fallbacks.

Pixel typography must be used only at integer sizes that render cleanly. Long
prose and application content retain readable conventional fonts when bitmap
text would reduce legibility.

### Icons and cursor

Prominent shell actions use a curated, packaged pixel-style icon set: launcher,
power/session controls, notification categories, and other high-visibility
symbols. GTK/Qt applications use a conventional dark icon theme recolored or
selected to harmonize with the palette. Icons must remain recognizable and
must not rely on color alone to communicate state.

The cursor should be a reproducible packaged theme with crisp edges and a size
appropriate for the laptop's scale. A custom cursor is not required unless an
existing package cannot meet those constraints.

## Theme Architecture

The wallpaper feeds one central token system, which then drives broad Stylix
coverage and focused per-application adapters:

```text
Chinatown wallpaper
        |
        v
Base16 palette + semantic tokens
        |
        +-- Stylix --> console, boot, fonts, terminals, supported applications
        |
        +-- system adapter --> greeter, cursor, shared font packages
        |
        `-- home adapters --> Hyprland, Waybar, Rofi, Mako, GTK/Qt,
                              Firefox, Thunderbird, Neovim, CLI tools
```

### Ownership boundaries

- `home/chinatown-pixel.yaml` owns the Base16 palette.
- `lib/repository.nix` owns the wallpaper reference, font metadata, cursor
  metadata, and semantic theme tokens shared by modules.
- `nixos/theme.nix` owns system font installation and Stylix system targets.
- `home/theme.nix` owns Home Manager Stylix targets and common GTK/Qt/Kvantum
  treatments.
- Existing application modules own their application-specific adapters.
- `home/desktop/waybar.nix` remains the only status-bar implementation.

Consumers refer to the central token attributes. They do not independently
derive palettes, copy color tables, or introduce a second theme abstraction.
Stylix remains responsible for applications it can theme correctly; a target
is disabled only where a focused adapter is required for exact geometry or
state styling.

## Surface Design

### Boot and greeter

Boot and console surfaces use the canvas color, restrained coral highlights,
and readable peach text. Plymouth and the greeter remain minimal: logo or
prompt, current user/session, input field, and failure state. Inputs use a dark
inset surface with a 2 px peach focus outline and a distinct red error border.

### Hyprland

Hyprland uses modest gaps aligned to the 4 px grid. Window borders are dark and
structural when inactive, coral/orange when active, and red for urgent states.
Rounded corners, blur, translucent inactive windows, soft shadows, and animated
decorative effects are disabled. Group/tab decoration follows the same state
roles.

### Waybar

Waybar is a full-width, edge-attached instrument rail rather than a floating
island. It uses a primary-surface background, a hard bottom structural border,
square modules, bitmap shell typography, and no gaps between arbitrary pills.

The left section contains the launcher identity, workspaces, and current
window. The center contains the clock. The right contains concise system
telemetry, network, audio, power profile, battery, and tray. Normal modules are
quiet; only active, warning, critical, muted, disconnected, and charging states
receive strong semantic color. Hover uses a raised surface and a crisp inner or
bottom edge. Tooltips reuse the menu/popup treatment.

Waybar is chosen over Quickshell, Noctalia, Ashell, and Eww because it provides
the required CSS precision without expanding the project into a custom desktop
shell or duplicating Rofi, Mako, and session controls.

### Rofi and session controls

Rofi uses a bordered dark panel with square input and list rows. Selection is a
coral/orange block with dark high-contrast text; keyboard focus also has a
visible outline. The launcher, window switcher, and power/session modes use the
same shell typography, padding, and icon rules.

### Notifications

Mako notifications use square dark cards, a structural outline, and a narrow
semantic edge for urgency. Titles, body text, progress, and action labels have
an explicit hierarchy. Critical notifications use red plus an urgency symbol
or label so color is not the only signal.

### GTK and Qt

GTK and Kvantum establish the shared application grammar: square headerbars,
hard dividers, immediate hover/pressed states, inset text fields, chunky
scrollbars, coral selection, and 2 px focus outlines. Controls may use a 1 px
bevel, but never soft shadows or rounded decoration. GTK and Qt should be
visually equivalent even when their implementation details differ.

PCManFM, file choosers, and dialogs inherit this treatment. Application content
keeps conventional readable typography while chrome follows Chinatown Pixel.

### Firefox and Thunderbird

Firefox `userChrome.css` themes browser chrome only: tab strip, toolbars,
sidebar, URL field, menus, and selected/attention states. Tabs remain square
and connected to the toolbar rather than floating pills. Private browsing and
security warnings remain distinguishable.

Thunderbird applies the same rules to its tab bar, folder tree, message list,
toolbars, search, and notifications. Unread, selected, flagged, and error states
must remain independently recognizable.

### Terminal, editor, and CLI

Kitty and Neovim receive the Base16 palette through Stylix, with explicit
adapter changes only for plugin chrome that retains rounded or mismatched
styling. Terminal/editor backgrounds use canvas or primary surface colors;
selections and active borders use coral/orange; diagnostics retain distinct
semantic hues.

Fish, Starship, Git/delta, bat, fzf, and btop use the same palette. Existing
Gruvbox and TwoDark references are removed from the active laptop path so a
single command-line workflow never changes visual language between tools.

## Interaction and Accessibility

Every interactive surface implements these states where supported:

- default;
- hover;
- active or pressed;
- keyboard focus;
- disabled;
- selected/current;
- informational;
- warning;
- critical/error;
- success/charging/connected.

Keyboard focus uses a 2 px peach outline separated from the control by a 1 px
dark edge where possible. Selection and urgency combine color with shape,
border, label, or icon changes. Small text and core controls target WCAG AA
contrast; lower contrast is limited to decorative structure and secondary
nonessential metadata. No state depends on animation or transparency.

## Reliability and Failure Handling

All theme assets must be declared by Nix and pinned or supplied by nixpkgs. A
missing font, icon, wallpaper, or cursor must fail evaluation/build rather than
silently downloading at activation time. Application adapters use conservative
fallback font stacks and standard symbolic icons where optional pixel assets
are unavailable.

The palette and semantic tokens are ordinary Nix data. Misspelled or removed
token attributes therefore fail evaluation at their consumer. No runtime color
generator, daemon, or mutable cache becomes part of the theme's source of
truth.

## Rollout

Implementation proceeds in five independently reviewable phases:

1. **Foundation:** palette, semantic tokens, wallpaper metadata, fonts, cursor,
   and core Stylix targets.
2. **Desktop shell:** Hyprland, Waybar, Rofi, Mako, and session controls.
3. **Toolkit layer:** GTK, Qt/Kvantum, icons, PCManFM, and dialogs.
4. **Applications:** Firefox, Thunderbird, Kitty, Neovim, Git/delta, and CLI
   tools.
5. **Consistency pass:** remove obsolete active-theme references, verify every
   state, and compare screenshots against the wallpaper.

Each phase must preserve a buildable `bandit` configuration. Existing unrelated
working-tree changes must be retained and reconciled rather than overwritten.

## Verification

Static and evaluation checks:

```bash
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
nix flake check --no-update-lock-file
nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
  --dry-run --no-update-lock-file
```

The implementation also searches the active laptop modules for obsolete
Gruvbox/TwoDark names, duplicated palette literals, nonzero radii, blur,
gradients, soft shadows, and decorative transparency. Each exception must be
intentional and documented locally.

Visual verification is performed after a test activation at the laptop's
normal scaling:

- capture the empty desktop, tiled and focused windows, Waybar states, Rofi,
  Mako at every urgency, GTK and Qt controls, Firefox, Thunderbird, Kitty, and
  Neovim;
- compare the screenshots with the wallpaper for palette, edge geometry,
  spacing rhythm, typography, and visual weight;
- navigate all core surfaces by keyboard and verify visible focus;
- exercise warning, critical, disconnected, muted, charging, selected, unread,
  and urgent states;
- confirm `bandit-lab` and dormant legacy desktop modules are unchanged.

## Acceptance Criteria

The design is complete when:

- the active `bandit` laptop presents one recognizable Chinatown Pixel visual
  system from boot through daily applications;
- the wallpaper, Base16 palette, and semantic tokens are the only active theme
  sources of truth;
- Waybar integrates visually with Hyprland, Rofi, and Mako without becoming a
  separate shell framework;
- active laptop modules contain no accidental Gruvbox or TwoDark styling;
- square geometry, crisp outlines, restrained pixel depth, and immediate state
  transitions are consistent across supported tools;
- focus, selection, warning, critical, and disabled states remain readable and
  distinguishable;
- all declared checks pass, and `bandit-lab` plus legacy desktop modules remain
  behaviorally unchanged.
