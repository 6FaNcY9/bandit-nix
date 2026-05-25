# Theming & UX Improvements — Design Spec

**Date:** 2026-05-25
**Repo:** bandit-nix (Framework 13 AMD 7040, NixOS unstable)
**Stylix scheme:** `gruvbox-dark-hard` (confirmed closest match to native nvim gruvbox hard)

---

## Scope

Six targeted changes to achieve system-wide gruvbox-dark-hard consistency and fix
CopyQ/Firefox UX issues. No new flake inputs required.

---

## 1. Unify nvim colors with the system

**Problem:** `stylix.targets.nixvim = false` in `home/theme.nix` means nvim runs its own
native gruvbox plugin, which produces marginally different intermediate shades compared
to the Stylix base16 hex values that kitty/GTK/fish use.

**Fix:**
- `home/theme.nix`: change `nixvim.enable` from `false` to `true`
- `home/editor.nix`: remove the `colorschemes.gruvbox` block entirely (Stylix injects
  base16-vim which covers it)
- `home/editor.nix`: change `plugins.lualine.settings.options.theme` from `"gruvbox"`
  to `"auto"` (lualine auto-detects the active colorscheme)

**Result:** nvim, kitty, fish, GTK apps all render identical `#1d2021` background and
identical accent hex values.

---

## 2. Qt theming

**Problem:** Qt apps (CopyQ, and any future Qt tool) receive no theme from Stylix because
Stylix manages GTK but not Qt directly. Qt falls back to its built-in white Fusion style.

**Fix:** Add to `nixos/desktop.nix`:
```nix
qt = {
  enable = true;
  platformTheme = "gtk2";
  style.name = "gtk2";
};
```
This tells all Qt5/Qt6 apps to pull their palette and widget style from the GTK2 theme,
which Stylix already manages as gruvbox-dark-hard.

---

## 3. CopyQ: floating window + tray-only startup

**Problem:**
- CopyQ has no i3 floating rule, so it opens as a tiled window.
- On boot, CopyQ opens its main window instead of silently going to the tray.

**Fix in `home/desktop/i3.nix`:**
- Add `{class = "copyq";}` to `floating.criteria` (class name is lowercase `copyq`).
- The existing startup command `${pkgs.copyq}/bin/copyq` already starts server-only
  and goes to tray — no change needed there. The window only appears when the
  `${mod}+Shift+v` toggle keybind is pressed.

---

## 4. Firefox

**Problem:** Firefox is referenced in i3 keybindings (`${mod}+Shift+w`) but the package
is not declared anywhere in the config, and there is no Stylix theming for it.

**Fix:**
- Create `home/desktop/firefox.nix`:
  ```nix
  { ... }: {
    programs.firefox.enable = true;
  }
  ```
- Add `./desktop/firefox.nix` to imports in `home/default.nix`.
- Add `stylix.targets.firefox.enable = true` to `home/theme.nix`.
  Stylix's firefox target injects a userChrome.css and color overrides derived from
  the active base16 scheme; it requires `programs.firefox.enable = true`.

**Note:** Firefox extensions, profiles, and search engines are out of scope for this spec.

---

## 5. LightDM theming + i3 window border colors

**Problem:**
- LightDM login screen is plain white because `stylix.targets.lightdm` is absent from
  `nixos/core.nix`.
- i3 window borders use i3's built-in defaults (grey) rather than gruvbox colors.

**Fix:**
- `nixos/core.nix` → add `targets.lightdm.enable = true` inside the existing
  `stylix.targets` block. Stylix will theme the LightDM GTK greeter background,
  colors, and font.
- `home/theme.nix` → add `targets.i3.enable = true`. Stylix sets i3's
  `client.focused`, `client.unfocused`, etc. from the base16 palette.

---

## 6. i3 autotiling

**Problem:** i3 uses manual split direction. Autotiling automatically chooses horizontal
or vertical split based on the focused container's aspect ratio.

**Fix in `home/desktop/i3.nix`:**
- Add `pkgs.i3-autotiling` to `home.packages`.
- Add startup entry:
  ```nix
  { command = "${pkgs.i3-autotiling}/bin/i3-autotiling"; notification = false; }
  ```
  Placed before the XFCE panel startup so tiling is active from the first window.

---

## Files changed

| File | Change |
|------|--------|
| `home/theme.nix` | nixvim `true`, firefox target, i3 target |
| `home/editor.nix` | remove colorschemes.gruvbox, lualine `"auto"` |
| `home/default.nix` | add `./desktop/firefox.nix` import |
| `home/desktop/firefox.nix` | new file — `programs.firefox.enable = true` |
| `home/desktop/i3.nix` | copyq float rule, i3-autotiling package + startup |
| `nixos/core.nix` | lightdm target |
| `nixos/desktop.nix` | qt platformTheme |

---

## Out of scope

- Firefox profile hardening, extensions, or search config
- Waybar / Wayland migration
- SOPS secrets changes
- Any changes to `stateVersion`
