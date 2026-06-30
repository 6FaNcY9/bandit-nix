{
  config,
  pkgs,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
in {
  # Refresh public IPv4 every 5 minutes — genmon-net reads the cached file.
  systemd.user.services.public-ip-refresh = {
    Unit.Description = "Refresh public IP cache";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.curl}/bin/curl -sf4 --max-time 8 https://icanhazip.com --output %t/public-ip-cache";
    };
  };

  systemd.user.timers.public-ip-refresh = {
    Unit.Description = "Refresh public IP every 5 minutes";
    Timer = {
      OnStartupSec = "5s";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
    Install.WantedBy = ["default.target"];
  };

  home = {
    packages = with pkgs; [
      xfce4-taskmanager
      xfce4-appfinder
    ];

    file = {
      # ── Genmon: network (IPv4 + up/down rates) ──────────────────
      ".local/bin/panel-net" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          IP_CACHE="$XDG_RUNTIME_DIR/public-ip-cache"
          if [[ -r "$IP_CACHE" ]] && [[ $(find "$IP_CACHE" -mmin -10 -print 2>/dev/null) ]]; then
            IPV4=$(tr -d '[:space:]' < "$IP_CACHE")
          else
            IPV4=""
          fi
          IPV4_DISPLAY=''${IPV4:-?.?.?.?}

          IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
          if [[ -z "$IFACE" ]]; then
            echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base0C}'>[</span><span color='${colors.base0C}'>󰓅 ''${IPV4_DISPLAY}</span><span color='${colors.base0C}'>]</span><span color='${colors.base02}'>─</span></txt>"
            exit 0
          fi

          # Pick icon: wifi vs ethernet
          if [[ -d "/sys/class/net/''${IFACE}/wireless" ]]; then
            NICON="󰖩"
          else
            NICON="󰈀"
          fi

          PREV="$XDG_RUNTIME_DIR/panel-net-prev-$IFACE"
          read -r prev_rx prev_tx < "$PREV" 2>/dev/null
          RX=$(awk -v i="$IFACE:" '$1==i {print $2}' /proc/net/dev)
          TX=$(awk -v i="$IFACE:" '$1==i {print $10}' /proc/net/dev)
          echo "$RX $TX" > "$PREV"

          if [[ -n "$prev_rx" && "$RX" -ge "$prev_rx" && "$TX" -ge "$prev_tx" ]]; then
            DRX=$(( (RX - prev_rx) / 1024 ))
            DTX=$(( (TX - prev_tx) / 1024 ))
          else
            DRX=0; DTX=0
          fi

          echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base0C}'>[</span><span color='${colors.base0C}'>''${NICON} ''${IPV4_DISPLAY}</span><span color='${colors.base0D}'> · </span><span color='${colors.base0B}'>↑''${DTX}k ↓''${DRX}k</span><span color='${colors.base0C}'>]</span><span color='${colors.base02}'>─</span></txt>"
        '';
      };

      # ── Genmon: CPU percentage ───────────────────────────────────
      ".local/bin/panel-cpu" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          read -r _ u n s i _ < /proc/stat
          PREV="$XDG_RUNTIME_DIR/panel-cpu-prev"
          read -r pu pn ps pi < "$PREV" 2>/dev/null || { pu=0; pn=0; ps=0; pi=0; }
          echo "$u $n $s $i" > "$PREV"
          USED=$(( (u + n + s) - (pu + pn + ps) ))
          TOTAL=$(( USED + (i - pi) ))
          if [[ "$TOTAL" -gt 0 ]]; then
            PCT=$(( USED * 100 / TOTAL ))
          else
            PCT=0
          fi
          if [[ "$PCT" -ge 80 ]]; then
            COLOR="${colors.base08}"
          elif [[ "$PCT" -ge 50 ]]; then
            COLOR="${colors.base09}"
          else
            COLOR="${colors.base0B}"
          fi
          echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base0B}'>[</span><span color=\"''${COLOR}\">󰻠 ''${PCT}%</span><span color='${colors.base0B}'>]</span><span color='${colors.base02}'>─</span></txt>"
        '';
      };

      # ── Genmon: RAM used ─────────────────────────────────────────
      ".local/bin/panel-mem" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          read -r USED TOTAL < <(awk '/^Mem:/{print $3, $2}' <(free -m --si))
          PCT=$(( USED * 100 / TOTAL ))
          DISPLAY=$(free -h --si | awk '/^Mem:/{print $3}')
          if [[ "$PCT" -ge 85 ]]; then
            COLOR="${colors.base08}"
          elif [[ "$PCT" -ge 60 ]]; then
            COLOR="${colors.base09}"
          else
            COLOR="${colors.base0A}"
          fi
          echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base09}'>[</span><span color=\"''${COLOR}\">󰍛 ''${DISPLAY}</span><span color='${colors.base09}'>]</span><span color='${colors.base02}'>─</span></txt>"
        '';
      };

      # ── Genmon: battery — shows [<profile-icon> <bat-icon> X%], click cycles power profile ──
      ".local/bin/panel-bat" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          BAT_DIR=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
          if [[ -z "$BAT_DIR" ]]; then
            echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base0E}'>[</span><span color='${colors.base0E}'>󰾅 · 󰁽 ?</span><span color='${colors.base0E}'>]</span><span color='${colors.base02}'>─</span></txt>"
            exit 0
          fi
          BAT=$(cat "$BAT_DIR/capacity" 2>/dev/null || echo "?")
          STATUS=$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")

          # Power profile icon + color
          PROFILE=$(powerprofilesctl get 2>/dev/null || echo "balanced")
          case "''${PROFILE}" in
            performance) PICON="󱐋"; PCOLOR="${colors.base08}" ;;
            power-saver) PICON="󰌪"; PCOLOR="${colors.base0B}" ;;
            *)           PICON="󰾅"; PCOLOR="${colors.base0A}" ;;
          esac

          # Battery icon + color
          if [[ "$STATUS" == "Charging" || "$STATUS" == "Full" ]]; then
            ICON="󰂄"; COLOR="${colors.base0B}"
          elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 10 ]]; then
            ICON="󰁺"; COLOR="${colors.base08}"
          elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 25 ]]; then
            ICON="󰁻"; COLOR="${colors.base09}"
          elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 50 ]]; then
            ICON="󰁽"; COLOR="${colors.base0A}"
          elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 75 ]]; then
            ICON="󰁿"; COLOR="${colors.base0B}"
          else
            ICON="󰂁"; COLOR="${colors.base0B}"
          fi

          echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base0E}'>[</span><span color=\"''${PCOLOR}\">''${PICON}</span><span color='${colors.base0D}'> · </span><span color=\"''${COLOR}\">''${ICON} ''${BAT}%</span><span color='${colors.base0E}'>]</span><span color='${colors.base02}'>─</span></txt><click>''${HOME}/.local/bin/panel-bat-click</click>"
        '';
      };

      # ── Cycles power profile: performance → balanced → power-saver → … ──
      ".local/bin/panel-bat-click" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          CURRENT=$(powerprofilesctl get 2>/dev/null || echo "balanced")
          case "$CURRENT" in
            performance) NEXT=balanced ;;
            balanced)    NEXT=power-saver ;;
            *)           NEXT=performance ;;
          esac
          powerprofilesctl set "$NEXT"
        '';
      };

      # ── Genmon: disk usage of / ─────────────────────────────────
      ".local/bin/panel-disk" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          read -r USED_H TOTAL_H PCT < <(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $3, $2, $5}')
          if [[ "$PCT" -ge 90 ]]; then
            COLOR="${colors.base08}"
          elif [[ "$PCT" -ge 75 ]]; then
            COLOR="${colors.base09}"
          else
            COLOR="${colors.base0B}"
          fi
          echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base0A}'>[</span><span color=\"''${COLOR}\">󰋊 ''${USED_H}/''${TOTAL_H}</span><span color='${colors.base0A}'>]</span><span color='${colors.base02}'>─</span></txt>"
        '';
      };

      # ── Genmon: Tor status ───────────────────────────────────────
      ".local/bin/panel-tor" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          if systemctl is-active --quiet tor 2>/dev/null; then
            echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base0E}'>[</span><span color='${colors.base0E}'>󰈀 tor</span><span color='${colors.base0E}'>]</span><span color='${colors.base02}'>─</span></txt>"
          else
            echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base02}'>[</span><span color='${colors.base02}'>󰈀 tor</span><span color='${colors.base02}'>]</span><span color='${colors.base02}'>─</span></txt>"
          fi
        '';
      };

      # ── Genmon: volume (left-click toggles mute) ─────────────────
      ".local/bin/panel-vol" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          VOL=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%')
          MUTED=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}')
          if [[ "$MUTED" == "yes" || -z "$VOL" ]]; then
            ICON="󰝟"; COLOR="${colors.base08}"; LABEL="mute"
          elif [[ "$VOL" -ge 70 ]]; then
            ICON="󰕾"; COLOR="${colors.base0B}"; LABEL="''${VOL}%"
          elif [[ "$VOL" -ge 30 ]]; then
            ICON="󰖀"; COLOR="${colors.base0B}"; LABEL="''${VOL}%"
          else
            ICON="󰕿"; COLOR="${colors.base03}"; LABEL="''${VOL}%"
          fi
          echo "<txt><span color='${colors.base02}'>─</span><span color='${colors.base0D}'>[</span><span color=\"''${COLOR}\">''${ICON} ''${LABEL}</span><span color='${colors.base0D}'>]</span><span color='${colors.base02}'>─</span></txt><click>pactl set-sink-mute @DEFAULT_SINK@ toggle</click>"
        '';
      };
    };
  };
}
