# XFCE4 Panel — Capabilities & Customization Research

## Panel Plugins Available

All configurable via `xfconf.settings."xfce4-panel"` in Home Manager.

### Menu plugins
- **applicationsmenu** — basic app menu, icon or text button
- **whiskermenu** (xfce4-whiskermenu-plugin) — **recommended**: searchable, category nav, recent/favorites, app icons, breadcrumbs, customizable CSS
  - xfconf key: `"plugins/plugin-N" = "whiskermenu"`
  - Config in `~/.config/xfce4/whiskermenu/` or xfconf `xfce4-whiskermenu-plugin`

### Status / system plugins
- **xfce4-systemload-plugin** — cpu/mem/swap/net bars, configurable colors, uptime display
- **xfce4-genmon-plugin** — runs any script, outputs to panel
  - Supports **Pango markup**: `<span color='#hex' weight='bold'>text</span>`
  - Wrapping needed: `<txt>pango markup here</txt>`
  - Also supports: `<img>path/to/icon.png</img>`, `<tool>tooltip text</tool>`, `<bar>0.75</bar>`
  - Multiple genmon instances per panel (one per stat is cleaner)
  - `update-period` in milliseconds
- **xfce4-sensors-plugin** — hardware sensor readings (lm-sensors backend)
- **xfce4-battery-plugin** — battery status and percentage
- **xfce4-netload-plugin** — upload/download rate display
- **xfce4-cpufreq-plugin** — CPU frequency per core
- **xfce4-cpugraph-plugin** — graph-style CPU usage

### Window management
- **tasklist** — open windows list, configurable grouping, icons, labels
- **pager** — workspace switcher, miniature view or numbers

### System tray / notifications
- **systray** — legacy X11 tray icons
- **statusnotifier** — modern D-Bus status notifier (replaces systray for modern apps)
- **notification-plugin** — notification history

### Utilities
- **separator** — separator line or transparent spacer (style 0=transparent/expand, 1=line)
- **clock** — digital/analog/binary, fully formattable
- **directorymenu** — browse folders from panel
- **launcher** — app launchers with icons, right-click for app chooser
- **places** — bookmarks/devices quick access

## Genmon Pango Markup Examples

```bash
#!/usr/bin/env bash
# CPU usage with color scaling
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2+$4)}')
if [ $CPU -gt 80 ]; then COLOR="#cc241d"
elif [ $CPU -gt 50 ]; then COLOR="#d79921"
else COLOR="#98971a"; fi
echo "<txt><span color='${COLOR}'> ${CPU}%</span></txt>"
```

```bash
#!/usr/bin/env bash
# Memory usage
TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
FREE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
USED=$(( (TOTAL - FREE) / 1024 ))
echo "<txt><span color='#d79921'> ${USED}M</span></txt>"
```

```bash
#!/usr/bin/env bash
# CPU temperature
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
TEMP_C=$(( TEMP / 1000 ))
if [ $TEMP_C -gt 80 ]; then COLOR="#cc241d"
elif [ $TEMP_C -gt 60 ]; then COLOR="#fe8019"
else COLOR="#98971a"; fi
echo "<txt><span color='${COLOR}'>󰔏 ${TEMP_C}°C</span></txt>"
```

## NixOS xfconf Configuration

The `xfconf.settings` Home Manager option sets XFCE configuration persistently via the xfconf database. Requires XFCE session to apply. On first login after `nixos-rebuild switch`, settings are applied.

**Important**: Panel needs restart after xfconf changes:
```bash
xfce4-panel -r
```

## Whiskermenu NixOS Setup

```nix
home.packages = [ pkgs.xfce.xfce4-whiskermenu-plugin ];
xfconf.settings."xfce4-panel"."plugins/plugin-1" = "whiskermenu";
xfconf.settings."xfce4-whiskermenu-plugin" = {
  "button-title" = "";
  "button-icon" = "nixos";  # or path to custom icon
  "show-button-title" = false;
  "show-button-icon" = true;
  "menu-width" = 500;
  "menu-height" = 600;
  "category-icon-size" = 16;
  "item-icon-size" = 22;
  "show-recent" = true;
  "recent-items-max" = 10;
};
```

## Sources
- Arch Linux Forums: xfce4-panel-genmon bash scripts (Pango markup confirmed)
- NixOS Discourse: Apply xfconf settings via home-manager
- XFCE official docs: https://docs.xfce.org/panel-plugins/start
