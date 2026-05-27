# XFCE Panel Design Spec

**Date:** 2026-05-28
**Status:** Approved for implementation

---

## Overview

Single top panel (30px) for the XFCE+i3 desktop on bandit (Framework 13 AMD).
Retro gruvbox aesthetic pulled from the new wallpaper (`com0570.jpg` — dark charcoal
background with horizontal stripes in green/teal/amber/red matching gruvbox palette).
Security-oriented metrics always visible. Compact — everything fits one row.

---

## Color Palette (from wallpaper)

| Role | Hex | Use |
|------|-----|-----|
| Panel background | `#111111` | Darker than wallpaper bg for contrast |
| Wallpaper bg | `#1e1e1e` | Desktop/window bg reference |
| Foreground | `#ebdbb2` | Primary text (gruvbox cream) |
| Muted text | `#a89984` | Labels, separators |
| Blue accent | `#458588` | App menu button, active workspace, focused window borders |
| Amber | `#d79921` | Clock, active task highlight, current workspace |
| Green | `#8ec07c` | Upload bandwidth |
| Red | `#cc241d` | Download bandwidth |
| Teal | `#689d6a` | CPU percentage |

---

## Wallpaper Change

New wallpaper: `~/Downloads/com0570.jpg` → copy to `hosts/bandit/wallpaper.jpg`
Update `nixos/core.nix`: `image = ../hosts/bandit/wallpaper.jpg;`

---

## Panel Layout (left → right)

```
[ ▸ apps ] | [ tasklist: kitty · firefox · copyq ] ··spacer·· [ cpu 12% · 1.2.3.4 ↑1.2k ↓48k ] | [ 1 ][ 2 ][ 3 ][ 4 ] | [ tray ] | [ Wed 14:22 ]
```

### Zones

| Zone | Plugin | Config |
|------|--------|--------|
| App menu | `applicationsmenu` | Button label "▸ apps", icon disabled |
| Separator | built-in separator | 1px line, 18px tall |
| Task list | `tasklist` | Current workspace only, flat buttons, icon+name, no grouping |
| (spacer) | `separator` | Expand mode — pushes right block to edge |
| CPU | `xfce4-systemload-plugin` | CPU % only, RAM hidden, click opens `xfce4-taskmanager` |
| Separator | built-in | thin |
| Public IP + net | `xfce4-genmon-plugin` | See genmon script below |
| Separator | built-in | thin |
| Workspaces | `xfce4-pager` | 1 row × 4 cols, mini squares (no labels), rows=1 |
| Separator | built-in | thin |
| System tray | `systray` | nm-applet, blueman-applet, battery, volume |
| Clock | `clock` | Format `%a %H:%M`, tooltip `%A %d %B %Y` |

### Metrics order rationale

`cpu% · IP · ↑↓ net` — CPU and bandwidth are adjacent for security correlation:
a CPU spike + bandwidth spike together signals anomalous activity visible in
one peripheral glance without consciously reading each value.

---

## Public IP + Bandwidth genmon Script

A single `xfce4-genmon-plugin` instance runs a wrapper script that outputs
both public IP and net I/O in one label. This avoids two separate plugins.

**Script:** `~/.local/bin/panel-netmon` (managed via `home.file`)

```bash
#!/usr/bin/env bash
# Reads cached public IP (refreshed by systemd timer every 60s).
# Reads /proc/net/dev for instantaneous bandwidth on the default interface.
# Never hangs the panel — all values read from files, no network calls inline.

CACHE="$XDG_RUNTIME_DIR/public-ip-cache"
IP=$(cat "$CACHE" 2>/dev/null || echo "—")

IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
if [[ -z "$IFACE" ]]; then
  echo "cpu — · — ↑— ↓—"
  exit 0
fi

read_bytes() {
  awk -v iface="$1:" '$1==iface {print $2" "$10}' /proc/net/dev
}

PREV_FILE="/tmp/netmon-prev-$IFACE"
read -r prev_rx prev_tx < "$PREV_FILE" 2>/dev/null
read -r rx tx < <(read_bytes "$IFACE")

if [[ -n "$prev_rx" ]]; then
  drx=$(( (rx - prev_rx) / 1024 ))
  dtx=$(( (tx - prev_tx) / 1024 ))
  [[ $drx -lt 0 ]] && drx=0
  [[ $dtx -lt 0 ]] && dtx=0
  NET="↑${dtx}k ↓${drx}k"
else
  NET="↑— ↓—"
fi

echo "$rx $tx" > "$PREV_FILE"
echo "$IP $NET"
```

**IP cache refresher:** `systemd.user.services.public-ip-refresh` — runs
`curl -sf --max-time 5 ifconfig.me > $XDG_RUNTIME_DIR/public-ip-cache`
every 60 seconds via a systemd user timer. Panel reads the file, never blocks.

**Genmon interval:** 1000ms (1s) for live bandwidth. IP updates independently
from the cache file.

---

## New Packages Required

Add to `home/desktop/i3.nix` or a new `home/desktop/panel.nix`:

```nix
home.packages = with pkgs; [
  xfce.xfce4-systemload-plugin
  xfce.xfce4-netload-plugin   # fallback / reference, genmon used for combined display
  xfce.xfce4-genmon-plugin
  xfce.xfce4-taskmanager      # opened on CPU click
  xfce.xfce4-appfinder        # Mod4+A
  papirus-icon-theme           # already present via dunst config
];
```

---

## Keybindings (i3)

Add to `home/desktop/i3.nix` `systemBindings`:

```nix
"${mod}+a" = "exec ${pkgs.xfce.xfce4-appfinder}/bin/xfce4-appfinder --collapsed";
```

`--collapsed` opens the compact run-dialog mode. `Mod4+Shift+A` could open
the full category browser if desired (not in scope for this spec).

---

## xfconf Panel Settings

Managed via `home/desktop/xfce-colors.nix` `xfconf.settings`:

```nix
"xfce4-panel" = {
  "panels/panel-1/position"         = "p=6;x=0;y=0";   # top, full width
  "panels/panel-1/position-locked"  = true;
  "panels/panel-1/size"             = 30;
  "panels/panel-1/length"           = 100;
  "panels/panel-1/background-style" = 1;                # solid color
  "panels/panel-1/background-color" = "#111111ff";
};
```

Panel plugin ordering and per-plugin config must be seeded via the panel XML
(`~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml`) on first run,
since xfconf plugin-ids are dynamic integers assigned at panel startup.
Implementation note: provide the XML as a `home.file` source.

---

## Files to Create / Modify

| File | Action |
|------|--------|
| `hosts/bandit/wallpaper.jpg` | Copy from `~/Downloads/com0570.jpg` |
| `nixos/core.nix` | Update wallpaper path to `.jpg` |
| `home/desktop/panel.nix` | New — packages, genmon script, systemd IP timer |
| `home/desktop/xfce-colors.nix` | Add panel position/color xfconf keys |
| `home/desktop/i3.nix` | Add `Mod4+A` appfinder binding |
| `home/default.nix` | Import `./desktop/panel.nix` |
| `.gitignore` | Add `.superpowers/` |

---

## Out of Scope

- Custom `.desktop` launcher entries for the app menu (user fills these in interactively via right-click → Edit Applications)
- `Mod4+Shift+A` for full appfinder browser mode
- Panel plugin for VPN status (genmon extension, future work)
- xfce4-notifyd panel plugin (dunst already handles notifications)
