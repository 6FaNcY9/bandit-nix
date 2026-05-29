{pkgs, ...}: {
  home.packages = with pkgs; [
    xfce4-systemload-plugin
    xfce4-genmon-plugin
    xfce4-taskmanager
    xfce4-appfinder
  ];

  # Writes cached public IP every 60s — genmon script reads the file, never blocks.
  systemd.user.services.public-ip-refresh = {
    Unit.Description = "Refresh public IP cache";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.curl}/bin/curl -sf --max-time 5 ifconfig.me --output %t/public-ip-cache";
    };
  };

  systemd.user.timers.public-ip-refresh = {
    Unit.Description = "Refresh public IP every 60s";
    Timer = {
      OnStartupSec = "5s";
      OnUnitActiveSec = "60s";
    };
    Install.WantedBy = ["default.target"];
  };

  # Genmon panel script — reads cached IP + /proc/net/dev, never hangs.
  home.file.".local/bin/panel-netmon" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      CACHE="$XDG_RUNTIME_DIR/public-ip-cache"
      IP=$(cat "$CACHE" 2>/dev/null || echo "—")

      IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
      if [[ -z "$IFACE" ]]; then
        echo "$IP ↑— ↓—"
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
        NET="↑''${dtx}k ↓''${drx}k"
      else
        NET="↑— ↓—"
      fi

      echo "$rx $tx" > "$PREV_FILE"
      echo "$IP $NET"
    '';
  };
}
