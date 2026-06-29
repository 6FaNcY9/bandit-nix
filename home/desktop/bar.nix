{pkgs, ...}: let
  pactl = "${pkgs.pipewire}/bin/pactl";
  rofi = "${pkgs.rofi}/bin/rofi";
in {
  services.polybar = {
    enable = true;
    package = pkgs.polybar.override {
      pulseSupport = true;
      i3Support = true;
    };

    # Kill XFCE panel (session manager starts it), then launch polybar
    script = ''
      pkill xfce4-panel 2>/dev/null || true
      polybar-msg cmd quit 2>/dev/null || true
      polybar main &
    '';

    settings = {
      "colors" = {
        bg = "#2d2d2d";
        bg1 = "#393939";
        bg3 = "#515151";
        fg = "#cccccc";
        muted = "#999999";
        green = "#99cc99";
        blue = "#6699cc";
        aqua = "#66cccc";
        yellow = "#ffcc66";
        orange = "#f99157";
        red = "#f2777a";
        purple = "#cc99cc";
      };

      # ── Main bar ────────────────────────────────────────────────────
      "bar/main" = {
        width = "100%";
        height = 26;
        background = "\${colors.bg1}";
        foreground = "\${colors.fg}";
        font-0 = "JetBrainsMono Nerd Font Mono:size=11;3";
        line-size = 0;
        padding-left = 0;
        padding-right = 0;
        module-margin = 0;
        modules-left = "nix sep i3";
        modules-right = "cpu mem net vol bat clock tray";
        wm-restack = "i3";
        cursor-click = "pointer";
        override-redirect = false;
        # Raised 3D look: bright highlight top, hard shadow bottom
        border-top-size = 2;
        border-bottom-size = 2;
        border-top-color = "#666666";
        border-bottom-color = "#111111";
      };

      # ── Left: NixOS menu button ─────────────────────────────────────
      "module/nix" = {
        type = "custom/text";
        format = " 󱄅 bandit ";
        format-foreground = "\${colors.blue}";
        format-background = "\${colors.bg1}";
        click-left = "${rofi} -show drun";
      };

      "module/sep" = {
        type = "custom/text";
        format = "│";
        format-foreground = "\${colors.bg3}";
      };

      # ── Left: i3 workspaces ─────────────────────────────────────────
      "module/i3" = {
        type = "internal/i3";
        format = "<label-state>";
        # focused: [ N ] in yellow
        label-focused = "[ %name% ]";
        label-focused-foreground = "\${colors.yellow}";
        label-focused-padding = 0;
        # unfocused: N muted
        label-unfocused = " %name% ";
        label-unfocused-foreground = "\${colors.muted}";
        label-unfocused-padding = 0;
        # visible (on other monitor)
        label-visible = " %name% ";
        label-visible-foreground = "\${colors.fg}";
        label-visible-padding = 0;
        # urgent: [ N ] in red
        label-urgent = "[ %name% ]";
        label-urgent-foreground = "\${colors.red}";
        label-urgent-padding = 0;
      };

      # ── Right: CPU (built-in, 3-level heat-map via warn) ─────────────
      "module/cpu" = {
        type = "internal/cpu";
        interval = 2;
        format = "%{F#515151}─[%{F-}%{F#99cc99}󰻠 <label>%{F#515151}]%{F-}";
        "format-warn" = "%{F#515151}─[%{F-}%{F#f2777a}󰻠 <label-warn>%{F#515151}]%{F-}";
        "warn-percentage" = 75;
        label = "%percentage%%";
        "label-warn" = "%percentage%%";
      };

      # ── Right: Memory (built-in, heat-map via warn) ────────────────
      "module/mem" = {
        type = "internal/memory";
        interval = 3;
        format = "%{F#515151}─[%{F-}%{F#ffcc66}󰍛 <label>%{F#515151}]%{F-}";
        "format-warn" = "%{F#515151}─[%{F-}%{F#f2777a}󰍛 <label-warn>%{F#515151}]%{F-}";
        "warn-percentage" = 85;
        label = "%used%";
        "label-warn" = "%used%";
      };

      # ── Right: Network ──────────────────────────────────────────────
      "module/net" = {
        type = "custom/script";
        exec = "/home/vino/.local/bin/bar-net";
        interval = 2;
      };

      # ── Right: Volume (built-in pulseaudio) ────────────────────────
      "module/vol" = {
        type = "internal/pulseaudio";
        sink = "@DEFAULT_SINK@";
        use-ui-max = false;
        interval = 5;
        format-volume = "%{F#515151}─[%{F-}<ramp-volume>%{F#cccccc}<label-volume>%{F-}%{F#515151}]%{F-}";
        format-muted = "%{F#515151}─[%{F-}%{F#f2777a}󰝟 mute%{F-}%{F#515151}]%{F-}";
        label-volume = "%percentage%%";
        ramp-volume-0 = "%{F#999999}󰕿 ";
        ramp-volume-1 = "%{F#99cc99}󰖀 ";
        ramp-volume-2 = "%{F#99cc99}󰕾 ";
        click-left = "${pactl} set-sink-mute @DEFAULT_SINK@ toggle";
        click-right = "pavucontrol &";
        scroll-up = "${pactl} set-sink-volume @DEFAULT_SINK@ +5%";
        scroll-down = "${pactl} set-sink-volume @DEFAULT_SINK@ -5%";
      };

      # ── Right: Battery ──────────────────────────────────────────────
      "module/bat" = {
        type = "custom/script";
        exec = "/home/vino/.local/bin/bar-bat";
        interval = 30;
        click-left = "/home/vino/.local/bin/bar-bat-cycle";
      };

      # ── Right: System tray ──────────────────────────────────────────
      "module/tray" = {
        type = "internal/tray";
        tray-spacing = "4px";
        tray-background = "\${colors.bg1}";
        tray-padding = "2px";
      };

      # ── Right: Clock ────────────────────────────────────────────────
      "module/clock" = {
        type = "internal/date";
        interval = 30;
        # Matches starship ─[ ] style
        date = "%{F#515151}─[%{F-} %{F#ffcc66}%a %d  %H:%M%{F-} %{F#515151}]%{F-}";
      };
    };
  };

  # ── Polybar scripts (output polybar %{F#color} tokens) ─────────────
  home.file = {
    ".local/bin/bar-net" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        IP_CACHE="$XDG_RUNTIME_DIR/public-ip-cache"
        if [[ -r "$IP_CACHE" ]] && [[ $(find "$IP_CACHE" -mmin -10 -print 2>/dev/null) ]]; then
          IPV4=$(tr -d '[:space:]' < "$IP_CACHE")
        fi
        IPV4=''${IPV4:-?.?.?.?}

        IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
        if [[ -z "$IFACE" ]]; then
          echo "%{F#515151}─[%{F-}%{F#66cccc}󰓅 ''${IPV4}%{F-}%{F#515151}]%{F-}"
          exit 0
        fi

        [[ -d "/sys/class/net/''${IFACE}/wireless" ]] && ICON="󰖩" || ICON="󰈀"

        PREV="$XDG_RUNTIME_DIR/bar-net-prev-$IFACE"
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

        echo "%{F#515151}─[%{F-}%{F#66cccc}''${ICON} ''${IPV4}%{F-}%{F#515151} · %{F-}%{F#99cc99}↑''${DTX}k ↓''${DRX}k%{F-}%{F#515151}]%{F-}"
      '';
    };

    ".local/bin/bar-bat" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        BAT_DIR=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
        if [[ -z "$BAT_DIR" ]]; then
          echo "%{F#515151}─[%{F-}%{F#515151}󰾅 · 󰁽 ?%{F-}%{F#515151}]%{F-}"
          exit 0
        fi
        BAT=$(cat "$BAT_DIR/capacity" 2>/dev/null || echo "?")
        STATUS=$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")
        PROFILE=$(powerprofilesctl get 2>/dev/null || echo "balanced")
        case "''${PROFILE}" in
          performance) PI="󱐋"; PC="#f2777a" ;;
          power-saver) PI="󰌪"; PC="#99cc99" ;;
          *)           PI="󰾅"; PC="#ffcc66" ;;
        esac
        if [[ "$STATUS" == "Charging" || "$STATUS" == "Full" ]]; then
          BI="󰂄"; BC="#99cc99"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 10 ]]; then BI="󰁺"; BC="#f2777a"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 25 ]]; then BI="󰁻"; BC="#f99157"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 50 ]]; then BI="󰁽"; BC="#ffcc66"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 75 ]]; then BI="󰁿"; BC="#99cc99"
        else BI="󰂁"; BC="#99cc99"; fi
        echo "%{F#515151}─[%{F-}%{F''${PC}}''${PI}%{F-}%{F#515151} · %{F-}%{F''${BC}}''${BI} ''${BAT}%%{F-}%{F#515151}]%{F-}"
      '';
    };

    ".local/bin/bar-bat-cycle" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        CURRENT=$(powerprofilesctl get 2>/dev/null || echo "balanced")
        case "$CURRENT" in
          performance) NEXT=balanced ;;
          balanced)    NEXT=power-saver ;;
          *)           NEXT=performance ;;
        esac
        powerprofilesctl set "$NEXT"
      '';
    };
  };

  home.packages = [pkgs.pavucontrol];
}
