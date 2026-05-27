# XFCE NixOS / Home Manager Customization Reference

Practical reference for customizing XFCE in a NixOS flake config using
Home Manager's `xfconf.settings`. This setup runs XFCE as session + i3 as WM
(xfwm4 disabled).

---

## How xfconf.settings works

Home Manager's `xfconf` module writes settings via `xfconf-query` at activation
time. NixOS-level `programs.xfconf.enable = true` is required (handles the
dconf/xfconf service).

```nix
xfconf.settings = {
  "channel-name" = {
    "property/path" = value;  # leading slash stripped automatically
  };
};
```

Types are inferred from Nix types: bool, int, float, string, list.

### Discovery workflow

```bash
# List all properties in a channel with their current values
xfconf-query -c xfce4-terminal -lv
xfconf-query -c xfce4-panel -lv
xfconf-query -c xsettings -lv
xfconf-query -c xfwm4 -lv

# Monitor live changes while configuring via GUI
xfconf-query -c xsettings -m

# List all channels
xfconf-query -l
```

---

## xfconf Channels Reference

### xsettings — GTK theme, fonts, DPI, cursor

> **Note:** Stylix overrides this channel when `stylix.targets.gtk.enable = true`.
> Set properties here only for non-Stylix values or when Stylix is disabled.

```nix
xfconf.settings."xsettings" = {
  "Net/ThemeName" = "gruvbox-dark-gtk";    # GTK theme name
  "Net/IconThemeName" = "Papirus-Dark";
  "Xft/DPI" = 96;
  "Xft/Antialias" = 1;
  "Xft/Hinting" = 1;
  "Xft/HintStyle" = "hintslight";
  "Xft/RGBA" = "rgb";
  "Gtk/CursorThemeName" = "Bibata-Modern-Classic";
  "Gtk/CursorThemeSize" = 24;
  "Gtk/FontName" = "JetBrainsMono Nerd Font 11";
  "Gtk/MonospaceFontName" = "JetBrainsMono Nerd Font Mono 12";
};
```

### xfce4-terminal — colors and appearance

```nix
xfconf.settings."xfce4-terminal" = {
  "color-use-theme" = false;
  "color-background" = "#272727";       # custom (darker than gruvbox bg)
  "color-foreground" = "#ebdbb2";
  "color-cursor" = "#ebdbb2";
  "color-bold-is-bright" = true;
  "scrollbar-style" = "TERMINAL_SCROLLBAR_NONE";  # hide scrollbar
  "font-name" = "JetBrainsMono Nerd Font Mono 12";
  "misc-tab-close-buttons" = false;
  "misc-borders-default" = false;       # remove default padding
  "misc-slim-tabs" = true;
  # 16-color gruvbox dark palette
  "color-palette" = "#282828;#cc241d;#98971a;#d79921;#458588;#b16286;#689d6a;#a89984;#928374;#fb4934;#b8bb26;#fabd2f;#83a598;#d3869b;#8ec07c;#ebdbb2";
};
```

### xfce4-panel — panel geometry and plugins

```nix
xfconf.settings."xfce4-panel" = {
  "panels" = [ 1 ];                     # one panel
  "panels/panel-1/size" = 28;           # height in pixels
  "panels/panel-1/position" = "p=8;x=0;y=0";  # top, full width
  "panels/panel-1/position-locked" = true;
  "panels/panel-1/background-style" = 1;       # solid color
  "panels/panel-1/background-color" = "#272727ff";  # rgba hex
  "panels/panel-1/length" = 100;               # 100% width
  # Plugin list — order matters; plugin IDs are arbitrary ints
  "panels/panel-1/plugin-ids" = [ 1 2 3 4 5 6 7 8 ];
  # Per-plugin config (plugin type by ID)
  "plugins/plugin-1/type" = "applicationsmenu";
  "plugins/plugin-2/type" = "tasklist";
  "plugins/plugin-3/type" = "separator";
  "plugins/plugin-4/type" = "clock";
  "plugins/plugin-5/type" = "systray";
};
```

### xfce4-session — startup and session management

```nix
xfconf.settings."xfce4-session" = {
  "general/LockCommand" = "${pkgs.i3lock}/bin/i3lock -c 262626";
  "general/SaveOnExit" = false;
  "startup/ssh-agent/enabled" = false;  # use gpg-agent SSH mode instead
};
```

### xfce4-power-manager

```nix
xfconf.settings."xfce4-power-manager" = {
  "xfce4-power-manager/blank-on-ac" = 5;       # minutes
  "xfce4-power-manager/dpms-on-ac-off" = 20;
  "xfce4-power-manager/brightness-on-battery" = 30;
  "xfce4-power-manager/lid-action-on-ac" = 1;  # 1=suspend
  "xfce4-power-manager/lid-action-on-battery" = 1;
};
```

### xfce4-notifyd — notification appearance

```nix
xfconf.settings."xfce4-notifyd" = {
  "theme" = "Default";
  "notify-location" = 2;    # 0=top-left, 1=top-right, 2=bottom-right, 3=bottom-left
  "expire-timeout" = 4000;  # milliseconds
  "initial-opacity" = 0.9;
};
```

---

## Making XFCE Look Retro / Square (No Rounded Corners)

GTK3 uses CSS for widget styling. Stylix generates the theme, but exposes an
`extraCss` hook to inject overrides. This zeroes out all border radii:

```nix
# home/theme.nix
stylix.targets.gtk.extraCss = ''
  * {
    border-radius: 0 !important;
    box-shadow: none !important;
  }
  headerbar,
  headerbar.titlebar { border-radius: 0 !important; }
  .csd .titlebar { border-radius: 0 !important; }
  popover.background,
  popover > contents { border-radius: 0 !important; }
  button,
  button.flat,
  button.suggested-action,
  button.destructive-action { border-radius: 0 !important; }
  entry,
  spinbutton { border-radius: 0 !important; }
  .menu,
  menuitem { border-radius: 0 !important; }
  tooltip { border-radius: 0 !important; }
  notebook > header tabs tab { border-radius: 0 !important; }
  treeview.view { border-radius: 0 !important; }
'';
```

> **Caveat:** Thunar's icon selection ring is hard-coded in C
> (`#define BORDER_RADIUS 8`) and cannot be removed via CSS alone.

### Additional retro tweaks via GTK settings

```nix
# home/theme.nix (alongside stylix.targets.gtk.extraCss)
gtk = {
  gtk3.extraConfig = {
    gtk-decoration-layout = "menu:";   # move buttons to left, no close button on right
    gtk-enable-animations = false;     # no fade/slide animations
    gtk-button-images = true;          # show icons in buttons (old-school)
    gtk-menu-images = true;            # show icons in menus
  };
  gtk4.extraConfig = {
    gtk-enable-animations = false;
  };
};
```

---

## Stylix XFCE target notes

The `stylix.targets.xfce` module (`autoEnable = false`, must opt in) only sets
**fonts** via xfconf — it does NOT set terminal colors. Colors must be set
manually via `xfconf.settings."xfce4-terminal"` as shown above.

See Stylix source: `/nix/store/<stylix>/modules/xfce/hm.nix`

---

## GTK theme packages (alternative to Stylix-generated)

If you want a pre-built gruvbox GTK theme instead of Stylix's generated one:

```nix
gtk.theme = {
  package = pkgs.gruvbox-dark-gtk;    # or pkgs.gruvbox-gtk-theme
  name = "gruvbox-dark-gtk";
};
```

But with Stylix active, `stylix.targets.gtk.enable = true` manages the theme.
Disable it or use `extraCss` for overrides.

---

## Debugging GTK theme application

```bash
# Check what GTK theme is actually active
gsettings get org.gnome.desktop.interface gtk-theme
xfconf-query -c xsettings -p /Net/ThemeName

# Verify Home Manager wrote the settings
cat ~/.config/gtk-3.0/settings.ini
cat ~/.config/gtk-3.0/gtk.css        # should contain your extraCss

# Force GTK theme reload without logout
xfsettingsd --replace &
gsettings reset org.gnome.desktop.interface gtk-theme
```

---

## Panel background color (workaround)

The `panels/panel-1/background-color` xfconf key expects RGBA hex (`#rrggbbaa`).
`background-style = 1` means solid color (0 = none/transparent, 2 = image).

If the panel ignores xfconf color settings, xfce4-panel may be reading its
own session XML. Edit `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml`
manually after first launch to seed initial values.
