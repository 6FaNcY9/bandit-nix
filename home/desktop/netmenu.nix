{pkgs, ...}: {
  home.packages = with pkgs; [
    xclip # for "copy public IP" action
  ];

  home.file = {
    # ── Panel chip: Tor status indicator (click → net-menu) ───────────────
    ".local/bin/panel-tor" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        if systemctl is-active --quiet tor-routing-enable.service 2>/dev/null; then
          echo "<txt><span color='#515151'>[</span><span color='#99cc99'>🧅 TOR</span><span color='#515151'>]</span></txt>"
        else
          echo "<txt><span color='#515151'>[</span><span color='#999999'>󰛳 net</span><span color='#515151'>]</span></txt>"
        fi
        echo "<click>/home/vino/.local/bin/net-menu</click>"
      '';
    };

    # ── Network + Tor rofi menu ────────────────────────────────────────────
    ".local/bin/net-menu" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        THEME="$HOME/.config/rofi/themes/retro-eighties.rasi"

        # ── Gather state ────────────────────────────────────────────────
        SSID=$(${pkgs.networkmanager}/bin/nmcli -t -f active,ssid dev wifi 2>/dev/null \
               | grep '^yes:' | cut -d: -f2 | head -1)
        LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
        PUBLIC_IP=$(cat "$XDG_RUNTIME_DIR/public-ip-cache" 2>/dev/null | tr -d '[:space:]')
        TOR_ON=false
        systemctl is-active --quiet tor-routing-enable.service 2>/dev/null && TOR_ON=true

        # ── Build menu items ─────────────────────────────────────────────
        ITEMS=""

        # Status header
        ITEMS+="── Status ──────────────────────────"$'\n'
        [[ -n "$SSID" ]]      && ITEMS+="󰖩  WiFi: $SSID"$'\n'
        [[ -z "$SSID" ]]      && ITEMS+="󰖪  WiFi: disconnected"$'\n'
        [[ -n "$LOCAL_IP" ]]  && ITEMS+="󰩟  Local:  $LOCAL_IP"$'\n'
        [[ -n "$PUBLIC_IP" ]] && ITEMS+="󰓅  Public: $PUBLIC_IP"$'\n'

        # Connections
        ITEMS+="── Connections ─────────────────────"$'\n'
        while IFS=: read -r name type state; do
          [[ -z "$name" ]] && continue
          case "$type" in
            *wifi*)     icon="󰖩" ;;
            *ethernet*) icon="󰈀" ;;
            *vpn*)      icon="󰌆" ;;
            *)          icon="󰛳" ;;
          esac
          ITEMS+="$icon  $name"$'\n'
        done < <(${pkgs.networkmanager}/bin/nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null)
        ITEMS+="󰐕  Connect / manage WiFi…"$'\n'

        # Tor toggle
        ITEMS+="── Tor ─────────────────────────────"$'\n'
        if $TOR_ON; then
          ITEMS+="🔓  Disable Tor routing"$'\n'
        else
          ITEMS+="🧅  Enable Tor routing"$'\n'
        fi
        ITEMS+="󰙀  Check Tor IP (browser)"$'\n'

        # Tools
        ITEMS+="── Tools ────────────────────────────"$'\n'
        ITEMS+="󰆒  Copy public IP to clipboard"$'\n'
        ITEMS+="󰒓  Network settings"$'\n'

        # ── Show menu ────────────────────────────────────────────────────
        CHOICE=$(printf '%s' "$ITEMS" \
          | ${pkgs.rofi}/bin/rofi -dmenu -p "  network" \
              -theme "$THEME" \
              -no-custom \
              -i)

        [[ -z "$CHOICE" ]] && exit 0

        # ── Handle selection ─────────────────────────────────────────────
        case "$CHOICE" in
          *"Enable Tor routing"*)
            systemctl start tor-routing-enable.service
            # Wait for Tor circuits then refresh IP — panel shows exit node IP
            (sleep 5 && systemctl --user start public-ip-refresh.service) &
            ;;
          *"Disable Tor routing"*)
            systemctl stop tor-routing-enable.service
            # Refresh immediately — panel shows real IP again
            systemctl --user start public-ip-refresh.service
            ;;
          *"Check Tor IP"*)
            ${pkgs.xdg-utils}/bin/xdg-open "https://check.torproject.org" &
            ;;
          *"Copy public IP"*)
            echo -n "$PUBLIC_IP" | ${pkgs.xclip}/bin/xclip -selection clipboard
            ;;
          *"Connect"*|*"manage WiFi"*)
            ${pkgs.networkmanagerapplet}/bin/nm-connection-editor &
            ;;
          *"Network settings"*)
            ${pkgs.networkmanagerapplet}/bin/nm-connection-editor &
            ;;
        esac
      '';
    };
  };
}
