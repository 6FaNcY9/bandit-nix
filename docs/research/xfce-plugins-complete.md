# XFCE Panel Plugins — Complete Reference

Source: Debian xfce4-goodies, Gentoo xfce-extra, NixOS nixpkgs (xfce.* scope)

## Full Plugin List (48 plugins)

### System Monitoring
| Plugin | NixOS package | Description |
|--------|--------------|-------------|
| xfce4-battery-plugin | `xfce.xfce4-battery-plugin` | Battery status with percentage + time remaining |
| xfce4-cpufreq-plugin | `xfce.xfce4-cpufreq-plugin` | CPU frequency and governor display |
| xfce4-cpugraph-plugin | `xfce.xfce4-cpugraph-plugin` | CPU usage graph (multi-core bars) |
| xfce4-diskperf-plugin | `xfce.xfce4-diskperf-plugin` | Disk I/O performance |
| xfce4-fsguard-plugin | `xfce.xfce4-fsguard-plugin` | Filesystem space monitor with alert |
| xfce4-netload-plugin | `xfce.xfce4-netload-plugin` | Network load graph (up/down) |
| xfce4-sensors-plugin | `xfce.xfce4-sensors-plugin` | Hardware sensors (temp, fan, voltage via lm_sensors) |
| xfce4-systemload-plugin | `xfce.xfce4-systemload-plugin` | CPU+MEM+swap text display |
| xfce4-taskmanager | `xfce.xfce4-taskmanager` | Task manager application |
| xfce4-thermal-plugin | built-in/sensors | Thermal zone display |

### Audio / Media
| Plugin | NixOS package | Description |
|--------|--------------|-------------|
| xfce4-pulseaudio-plugin | `xfce.xfce4-pulseaudio-plugin` | Volume slider, media keys, mpris controls |
| xfce4-mixer | `xfce.xfce4-mixer` | Legacy ALSA mixer (prefer pulseaudio) |
| xfce4-mpc-plugin | `xfce.xfce4-mpc-plugin` | MPD client panel control |

### Network / Wireless
| Plugin | NixOS package | Description |
|--------|--------------|-------------|
| xfce4-wavelan-plugin | `xfce.xfce4-wavelan-plugin` | WiFi signal strength display |
| network-manager-applet | `networkmanagerapplet` | NM tray icon (already used) |

### Power Management
| Plugin | NixOS package | Description |
|--------|--------------|-------------|
| xfce4-power-manager-plugins | `xfce.xfce4-power-manager` | Power profile + brightness tray icon |

### Productivity / Launcher
| Plugin | NixOS package | Description |
|--------|--------------|-------------|
| xfce4-verve-plugin | `xfce.xfce4-verve-plugin` | Inline command launcher bar (like dmenu but in panel) |
| xfce4-notes-plugin | `xfce.xfce4-notes-plugin` | Sticky notes |
| xfce4-clipman-plugin | `xfce.xfce4-clipman-plugin` | Clipboard manager (similar to copyq) |
| xfce4-timer-plugin | `xfce.xfce4-timer-plugin` | Countdown/stopwatch |

### Window Management
| Plugin | NixOS package | Description |
|--------|--------------|-------------|
| xfce4-taskbar-plugin | built-in | Window tasklist (already: flat buttons) |
| xfce4-windowck-plugin | `xfce.xfce4-windowck-plugin` | Show active window title+buttons on panel |
| xfce4-docklike-plugin | `xfce.xfce4-docklike-plugin` | macOS-dock style icon-only tasklist with running indicators |

### Clock / Date
| Plugin | NixOS package | Description |
|--------|--------------|-------------|
| xfce4-datetime-plugin | `xfce.xfce4-datetime-plugin` | Rich clock with calendar popup, custom format |
| xfce4-time-out-plugin | `xfce.xfce4-time-out-plugin` | Break reminder (Pomodoro-style) |

### Desktop / Display
| Plugin | NixOS package | Description |
|--------|--------------|-------------|
| xfce4-screenshooter | `xfce.xfce4-screenshooter` | Screenshot tool with panel button |
| xfce4-show-desktop-plugin | built-in | Show desktop button |
| xfce4-pager-plugin | built-in | Workspace pager (already used) |
| xfce4-action-buttons | built-in | Lock/logout/shutdown buttons |

### Scripted / Custom
| Plugin | NixOS package | Description |
|--------|--------------|-------------|
| xfce4-genmon-plugin | `xfce.xfce4-genmon-plugin` | Execute any script, display output with Pango markup |

## Recommended for bandit (Framework 13 + XFCE+i3 + gruvbox)

### Must-have
1. **xfce4-pulseaudio-plugin** — volume control, media keys (mpris), replaces systray icon
2. **xfce4-battery-plugin** — laptop, shows % + time remaining
3. **xfce4-sensors-plugin** — hardware temp (replaces genmon temp script, more accurate)
4. **xfce4-power-manager-plugins** — brightness tray, power profile quick toggle

### Nice-to-have
5. **xfce4-wavelan-plugin** — WiFi signal strength (Framework 13 has wifi)
6. **xfce4-fsguard-plugin** — disk space alert for root / home
7. **xfce4-screenshooter** — screenshot button on panel
8. **xfce4-verve-plugin** — inline launcher (fast alt to rofi for quick commands)
9. **xfce4-windowck-plugin** — show focused window title on panel (retro aesthetic)

### Skip (covered by other tools)
- xfce4-clipman → already have copyq
- xfce4-taskmanager → use htop/btop in terminal
- xfce4-mixer → covered by pulseaudio-plugin
- xfce4-docklike-plugin → macOS dock style, user prefers icon+name tasklist

## Panel Layout (updated with recommendations)

```
[❄ bandit ▾] | [kitty] [firefox] [nvim] ... | spacer | [󰓅 1.2.3.x ↑↓] [󰻠 12%] [󰍛 2.1G] [󰔏 48°C] | [1][2][3] | [vol] [bat] [wifi] [pwr] | Thu 09:12
```

## NixOS Package Names (confirmed in nixpkgs)

```nix
home.packages = with pkgs; [
  xfce.xfce4-pulseaudio-plugin
  xfce.xfce4-battery-plugin
  xfce.xfce4-sensors-plugin
  xfce.xfce4-power-manager   # includes power-manager-plugins
  xfce.xfce4-wavelan-plugin
  xfce.xfce4-fsguard-plugin
  xfce.xfce4-screenshooter
];
```

## Sources
- Debian xfce4-goodies metapackage list
- Gentoo xfce-extra category
- NixOS nixpkgs xfce scope (all under `pkgs.xfce.*`)
- NixOS XFCE wiki: https://nixos.wiki/wiki/Xfce
