{pkgs, ...}: let
  pactl = "${pkgs.pipewire}/bin/pactl";
  rofi = "${pkgs.rofi}/bin/rofi";
in {
  services.polybar = {
    enable = true;
    package = pkgs.polybar;

    # Kill any running instance then relaunch on i3 reload
    script = ''
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
        background = "\${colors.bg}";
        foreground = "\${colors.fg}";
        font-0 = "JetBrainsMono Nerd Font Mono:size=11;3";
        line-size = 0;
        padding-left = 0;
        padding-right = 0;
        module-margin = 0;
        modules-left = "nix sep i3";
        modules-right = "cpu mem net vol bat tray clock";
        wm-restack = "i3";
        cursor-click = "pointer";
        override-redirect = false;
      };

      # ── Left: NixOS menu button ─────────────────────────────────────
      "module/nix" = {
        type = "custom/text";
        content = " ❄ bandit ";
        content-foreground = "\${colors.blue}";
        content-background = "\${colors.bg}";
        click-left = "${rofi} -show drun";
      };

      "module/sep" = {
        type = "custom/text";
        content = "│";
        content-foreground = "\${colors.bg3}";
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

      # ── Right: CPU ──────────────────────────────────────────────────
      "module/cpu" = {
        type = "custom/script";
        exec = "/home/vino/.local/bin/bar-cpu";
        interval = 2;
      };

      # ── Right: Memory ───────────────────────────────────────────────
      "module/mem" = {
        type = "custom/script";
        exec = "/home/vino/.local/bin/bar-mem";
        interval = 3;
      };

      # ── Right: Network ──────────────────────────────────────────────
      "module/net" = {
        type = "custom/script";
        exec = "/home/vino/.local/bin/bar-net";
        interval = 2;
      };

      # ── Right: Volume ───────────────────────────────────────────────
      "module/vol" = {
        type = "custom/script";
        exec = "/home/vino/.local/bin/bar-vol";
        interval = 1;
        click-left = "${pactl} set-sink-mute @DEFAULT_SINK@ toggle";
        scroll-up = "${pactl} set-sink-volume @DEFAULT_SINK@ +5%";
        scroll-down = "${pactl} set-sink-volume @DEFAULT_SINK@ -5%";
      };

      # ── Right: Battery ──────────────────────────────────────────────
      "module/bat" = {
        type = "custom/script";
        exec = "/home/vino/.local/bin/bar-bat";
        interval = 30;
        click-left = "/home/vino/.local/bin/panel-bat-click";
      };

      # ── Right: System tray ──────────────────────────────────────────
      "module/tray" = {
        type = "internal/tray";
        tray-spacing = "4px";
        tray-background = "\${colors.bg}";
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
    ".local/bin/bar-cpu" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        read -r _ u n s i _ < /proc/stat
        PREV="$XDG_RUNTIME_DIR/bar-cpu-prev"
        read -r pu pn ps pi < "$PREV" 2>/dev/null || { pu=0; pn=0; ps=0; pi=0; }
        echo "$u $n $s $i" > "$PREV"
        USED=$(( (u + n + s) - (pu + pn + ps) ))
        TOTAL=$(( USED + (i - pi) ))
        PCT=0
        [[ "$TOTAL" -gt 0 ]] && PCT=$(( USED * 100 / TOTAL ))
        if   [[ "$PCT" -ge 80 ]]; then C="#f2777a"
        elif [[ "$PCT" -ge 50 ]]; then C="#f99157"
        else C="#99cc99"; fi
        echo "%{F#515151}─[%{F-}%{F''${C}}󰻠 ''${PCT}%%{F-}%{F#515151}]%{F-}"
      '';
    };

    ".local/bin/bar-mem" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        read -r USED TOTAL < <(awk '/^Mem:/{print $3, $2}' <(free -m --si))
        PCT=0; [[ "$TOTAL" -gt 0 ]] && PCT=$(( USED * 100 / TOTAL ))
        DISPLAY=$(free -h --si | awk '/^Mem:/{print $3}')
        if   [[ "$PCT" -ge 85 ]]; then C="#f2777a"
        elif [[ "$PCT" -ge 60 ]]; then C="#f99157"
        else C="#ffcc66"; fi
        echo "%{F#515151}─[%{F-}%{F''${C}}󰍛 ''${DISPLAY}%{F-}%{F#515151}]%{F-}"
      '';
    };

    ".local/bin/bar-net" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
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

    ".local/bin/bar-vol" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        VOL=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%')
        MUTED=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}')
        if [[ "$MUTED" == "yes" || -z "$VOL" ]]; then
          echo "%{F#515151}─[%{F-}%{F#f2777a}󰝟 mute%{F-}%{F#515151}]%{F-}"
        elif [[ "$VOL" -ge 70 ]]; then
          echo "%{F#515151}─[%{F-}%{F#99cc99}󰕾 ''${VOL}%%{F-}%{F#515151}]%{F-}"
        elif [[ "$VOL" -ge 30 ]]; then
          echo "%{F#515151}─[%{F-}%{F#99cc99}󰖀 ''${VOL}%%{F-}%{F#515151}]%{F-}"
        else
          echo "%{F#515151}─[%{F-}%{F#999999}󰕿 ''${VOL}%%{F-}%{F#515151}]%{F-}"
        fi
      '';
    };

    ".local/bin/bar-bat" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
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
  };
}
