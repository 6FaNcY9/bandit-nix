{pkgs, ...}: {
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
            echo "<txt><span color='#515151'>[</span><span color='#66cccc'>󰓅</span> <span color='#6699cc'>''${IPV4_DISPLAY}</span><span color='#515151'>]</span></txt>"
            exit 0
          fi

          PREV="$XDG_RUNTIME_DIR/panel-net-prev-$IFACE"
          read -r prev_rx prev_tx < "$PREV" 2>/dev/null
          RX=$(awk -v i="$IFACE:" '$1==i {print $2}' /proc/net/dev)
          TX=$(awk -v i="$IFACE:" '$1==i {print $10}' /proc/net/dev)
          echo "$RX $TX" > "$PREV"

          if [[ -n "$prev_rx" && "$RX" -ge "$prev_rx" ]]; then
            DRX=$(( (RX - prev_rx) / 1024 ))
            DTX=$(( (TX - prev_tx) / 1024 ))
          else
            DRX=0; DTX=0
          fi

          echo "<txt><span color='#515151'>[</span><span color='#66cccc'>󰓅</span> <span color='#6699cc'>''${IPV4_DISPLAY}</span> <span color='#99cc99'>↑''${DTX}k ↓''${DRX}k</span><span color='#515151'>]</span></txt>"
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
          echo "<txt><span color='#515151'>[</span><span color='#99cc99'><span size='18432'>󰻠</span> ''${PCT}%</span><span color='#515151'>]</span></txt>"
        '';
      };

      # ── Genmon: RAM used ─────────────────────────────────────────
      ".local/bin/panel-mem" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          MEM=$(free -h --si | awk '/^Mem:/{print $3}')
          echo "<txt><span color='#515151'>[</span><span color='#ffcc66'>󰍛 ''${MEM}</span><span color='#515151'>]</span></txt>"
        '';
      };

      # ── Genmon: battery (color-coded, icon tracks charge level) ──
      ".local/bin/panel-bat" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          BAT_DIR=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
          if [[ -z "$BAT_DIR" ]]; then
            echo "<txt><span color='#515151'>[</span><span color='#999999'>󰁽 ?</span><span color='#515151'>]</span></txt>"
            exit 0
          fi
          BAT=$(cat "$BAT_DIR/capacity" 2>/dev/null || echo "?")
          STATUS=$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")
          if [[ "$STATUS" == "Charging" || "$STATUS" == "Full" ]]; then
            ICON="󰂄"; COLOR="#99cc99"
          elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 10 ]]; then
            ICON="󰁺"; COLOR="#f2777a"
          elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 25 ]]; then
            ICON="󰁻"; COLOR="#f99157"
          elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 50 ]]; then
            ICON="󰁽"; COLOR="#ffcc66"
          elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 75 ]]; then
            ICON="󰁿"; COLOR="#99cc99"
          else
            ICON="󰂁"; COLOR="#99cc99"
          fi
          echo "<txt><span color='#515151'>[</span><span color=\"''${COLOR}\">''${ICON} ''${BAT}%</span><span color='#515151'>]</span></txt>"
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
            ICON="󰝟"; COLOR="#f2777a"; LABEL="mute"
          elif [[ "$VOL" -ge 70 ]]; then
            ICON="󰕾"; COLOR="#99cc99"; LABEL="''${VOL}%"
          elif [[ "$VOL" -ge 30 ]]; then
            ICON="󰖀"; COLOR="#99cc99"; LABEL="''${VOL}%"
          else
            ICON="󰕿"; COLOR="#999999"; LABEL="''${VOL}%"
          fi
          echo "<txt><span color='#515151'>[</span><span color=\"''${COLOR}\">''${ICON} ''${LABEL}</span><span color='#515151'>]</span></txt><click>pactl set-sink-mute @DEFAULT_SINK@ toggle</click>"
        '';
      };
    };
  };
}
