{pkgs, ...}: {
  home.packages = with pkgs; [
    xfce4-whiskermenu-plugin
    xfce4-genmon-plugin
    xfce4-pulseaudio-plugin
    xfce4-battery-plugin
    xfce4-sensors-plugin
    xfce4-power-manager
    xfce4-netload-plugin
    xfce4-screenshooter
    xfce4-taskmanager
    xfce4-appfinder
    lm_sensors
  ];

  # Refresh public IPv4 every 5 minutes — genmon-net reads the cached file.
  systemd.user.services.public-ip-refresh = {
    Unit.Description = "Refresh public IP cache";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.curl}/bin/curl -sf4 --max-time 8 https://ifconfig.me --output %t/public-ip-cache";
    };
  };

  systemd.user.timers.public-ip-refresh = {
    Unit.Description = "Refresh public IP every 5 minutes";
    Timer = {
      OnStartupSec = "5s";
      OnUnitActiveSec = "5min";
    };
    Install.WantedBy = ["default.target"];
  };

  # ── Genmon: network (IPv4 + up/down rates) ──────────────────
  home.file.".local/bin/panel-net" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      IPV4=$(cat "$XDG_RUNTIME_DIR/public-ip-cache" 2>/dev/null || echo "?.?.?.?")
      IPV4_DISPLAY=''${IPV4%.*}.x

      IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
      if [[ -z "$IFACE" ]]; then
        echo "<txt><span color='#478789'>󰓅</span> <span color='#458588'>''${IPV4_DISPLAY}</span></txt>"
        exit 0
      fi

      PREV="/tmp/panel-net-prev-$IFACE"
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

      echo "<txt><span color='#478789'>󰓅</span> <span color='#458588'>''${IPV4_DISPLAY}</span> <span color='#83a598'>↑''${DTX}k ↓''${DRX}k</span></txt>"
    '';
  };

  # ── Genmon: CPU percentage ───────────────────────────────────
  home.file.".local/bin/panel-cpu" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      read -r _ u n s i _ < /proc/stat
      PREV="/tmp/panel-cpu-prev"
      read -r pu pn ps pi < "$PREV" 2>/dev/null || { pu=0; pn=0; ps=0; pi=0; }
      echo "$u $n $s $i" > "$PREV"
      USED=$(( (u + n + s) - (pu + pn + ps) ))
      TOTAL=$(( USED + (i - pi) ))
      if [[ "$TOTAL" -gt 0 ]]; then
        PCT=$(( USED * 100 / TOTAL ))
      else
        PCT=0
      fi
      echo "<txt><span color='#98971a'>󰻠</span> <span color='#b8bb26'>''${PCT}%</span></txt>"
    '';
  };

  # ── Genmon: RAM used ─────────────────────────────────────────
  home.file.".local/bin/panel-mem" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      MEM=$(free -h --si | awk '/^Mem:/{print $3}')
      echo "<txt><span color='#d79921'>󰍛</span> <span color='#fabd2f'>''${MEM}</span></txt>"
    '';
  };
}
