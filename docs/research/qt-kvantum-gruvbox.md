# Qt Theming with Kvantum — Gruvbox Research

## Best Gruvbox Kvantum Themes

### 1. gruvbox-kvantum-themes by sachnr (RECOMMENDED)
- KDE Store: https://store.kde.org/p/1976481
- GitHub: https://github.com/sachnr/gruvbox-kvantum-themes
- Variants: Gruvbox-Dark-Green, Gruvbox-Dark-Brown, Gruvbox-Dark-Blue
- **Gruvbox-Dark-Green** best matches the bandit wallpaper (forest green tones)

### 2. Gruvbox-Kvantum by TheSerphh
- GitHub: https://github.com/TheSerphh/Gruvbox-Kvantum
- Supports Qt5 and Qt6
- Single variant, closer to standard gruvbox-dark

## NixOS Implementation

```nix
# In home/theme.nix or new home/qt.nix

home.packages = with pkgs; [
  libsForQt5.qtstyleplugin-kvantum  # Qt5
  qt6Packages.qtstylepluginkvantum   # Qt6
  qt5ct                              # Qt5 configuration tool
  qt6ct                              # Qt6 configuration tool
];

# Write Kvantum theme files
xdg.configFile."Kvantum/gruvbox-dark/gruvbox-dark.kvconfig".source = ./kvantum/gruvbox-dark.kvconfig;
xdg.configFile."Kvantum/gruvbox-dark/gruvbox-dark.svg".source = ./kvantum/gruvbox-dark.svg;
xdg.configFile."Kvantum/kvantum.kvconfig".text = ''
  [General]
  theme=gruvbox-dark
'';

# Qt platform theme and style
home.sessionVariables = {
  QT_QPA_PLATFORMTHEME = "qt5ct";
  QT_STYLE_OVERRIDE = "kvantum";
};
```

## Kvantum Config File Structure

A `.kvconfig` file defines colors and widget styles:
```ini
[General]
author=sachnr
description=Gruvbox Dark Green

[PanelButtonCommand]
frame.element=button
frame.top=3
frame.bottom=3
frame.left=3
frame.right=3
interior=true
interior.element=button
...
```

## Alternative: Qt5ct + Fusion style

For a simpler approach without SVG themes:
```nix
xdg.configFile."qt5ct/qt5ct.conf".text = ''
  [Appearance]
  style=Fusion
  color_scheme_path=/path/to/gruvbox.conf

  [Fonts]
  fixed=@Variant(...)
  general=@Variant(...)
'';
```

Fusion style supports color palettes and is lighter than Kvantum.

## Applying in X11 (important for XFCE+i3)

For Qt5 apps to pick up the theme, the env vars must be set BEFORE the session starts.
In NixOS this is done via `home.sessionVariables` which writes to `~/.profile` (sourced by the X session).

If using fish shell, also add to `fish.shellInit`:
```fish
set -x QT_QPA_PLATFORMTHEME qt5ct
set -x QT_STYLE_OVERRIDE kvantum
```

## Sources
- KDE Store: https://store.kde.org/p/1976481
- GitHub: https://github.com/TheSerphh/Gruvbox-Kvantum
- AUR: https://aur.archlinux.org/packages/kvantum-theme-gruvbox-git
