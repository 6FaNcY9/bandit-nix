{
  config,
  pkgs,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  pactl = "${pkgs.pipewire}/bin/pactl";
  rofi = "${pkgs.rofi}/bin/rofi";
  # Polybar format helpers.
  # The rails are the connecting "─" glyphs; brackets use the module accent.
  lb = color: "%{F${color}}[%{F-} ";
  rb = color: " %{F${color}}]%{F-}%{F${colors.base02}}─%{F-}";
  rbLine = color: " %{F${color}}]%{F-}%{F${colors.base02}}─%{F-}";
  # Centered modules need their own leading rail because they do not touch neighbors.
  lbLine = color: "%{F${colors.base02}}─%{F-}%{F${color}}[%{F-} ";
  # Font selectors: T2 is the larger icon font; T3 is the slightly smaller battery font.
  icon = glyph: "%{T2}${glyph}%{T-}";
  batteryIcon = glyph: "%{T4}${glyph}%{T-}";
in {
  services.polybar = {
    enable = true;
    package = pkgs.polybar.override {
      pulseSupport = true;
      i3Support = true;
    };

    script = ''
      export PATH="${pkgs.coreutils}/bin:${pkgs.gawk}/bin:${pkgs.iproute2}/bin:${pkgs.power-profiles-daemon}/bin:/run/current-system/sw/bin:$PATH"
      pkill xfce4-panel 2>/dev/null || true
      polybar-msg cmd quit 2>/dev/null || true
      polybar main &
    '';

    settings = {
      "colors" = {
        bg = colors.base00;
        bg1 = colors.base01;
        bg3 = colors.base02;
        fg = colors.base05;
        muted = colors.base03;
        green = colors.base0B;
        blue = colors.base0D;
        aqua = colors.base0C;
        yellow = colors.base0A;
        orange = colors.base09;
        red = colors.base08;
        purple = colors.base0E;
      };

      "bar/main" = {
        width = "100%";
        height = 38;
        background = "\${colors.bg}";
        foreground = "\${colors.fg}";
        font-0 = "JetBrainsMono Nerd Font Mono:style=Bold:size=13;4";
        font-1 = "JetBrainsMono Nerd Font Mono:style=Bold:size=17;5";
        font-2 = "JetBrainsMono Nerd Font Mono:style=Bold:size=15;4";
        locale = "en_US.UTF-8";
        line-size = 0;
        padding-left = 0;
        padding-right = 1;
        module-margin = 0;
        modules-left = "nix i3";
        modules-center = "clock";
        modules-right = "cpu mem net vol bat tray";
        wm-restack = "i3";
        cursor-click = "pointer";
        override-redirect = false;
        border-top-size = 0;
        border-bottom-size = 1;
        border-bottom-color = "\${colors.bg3}";
      };

      # ── Left: hostname — matches starship ─[ hostname ] style ─────────
      "module/nix" = {
        type = "custom/text";
        format = "${lb colors.base0D}%{F${colors.base0C}}${icon "󱄅"}%{F-} %{F${colors.base0D}}bandit%{F-}${rb colors.base0D}";
        click-left = "${rofi} -show drun";
      };

      # ── Left: i3 workspaces — focused [ N ] yellow, rest dim ──────────
      "module/i3" = {
        type = "internal/i3";
        format = "<label-state>";
        label-focused = "${lb colors.base0A}%{F${colors.base0A}}%name%%{F-}${rbLine colors.base0A}";
        label-focused-padding = 0;
        label-unfocused = " %{F${colors.base03}}%name%%{F-} %{F${colors.base02}}─%{F-}";
        label-unfocused-padding = 0;
        label-visible = " %{F${colors.base03}}%name%%{F-} %{F${colors.base02}}─%{F-}";
        label-visible-padding = 0;
        label-urgent = "${lb colors.base08}%{F${colors.base08}}%name%%{F-}${rbLine colors.base08}";
        label-urgent-padding = 0;
      };

      # ── Center: clock — dim date · bold yellow time ───────────────────
      "module/clock" = {
        type = "internal/date";
        interval = 10;
        date = "%a %d";
        time = "%H:%M";
        label = "${lbLine colors.base0E}%{F${colors.base03}}%date%%{F-}  %{F${colors.base0A}}%time%%{F-}${rbLine colors.base0E}";
      };

      # ── Right: CPU ────────────────────────────────────────────────────
      "module/cpu" = {
        type = "internal/cpu";
        interval = 2;
        format = "${lbLine colors.base0B}%{F${colors.base0B}}${icon "󰻠"} <label>%{F-}${rb colors.base0B}";
        "format-warn" = "${lbLine colors.base08}%{F${colors.base08}}${icon "󰻠"} <label-warn>%{F-}${rb colors.base08}";
        "warn-percentage" = 75;
        label = "%percentage%%";
        "label-warn" = "%percentage%%";
      };

      # ── Right: Memory ─────────────────────────────────────────────────
      "module/mem" = {
        type = "internal/memory";
        interval = 3;
        format = "${lb colors.base09}%{F${colors.base09}}${icon "󰍛"} <label>%{F-}${rb colors.base09}";
        "format-warn" = "${lb colors.base08}%{F${colors.base08}}${icon "󰍛"} <label-warn>%{F-}${rb colors.base08}";
        "warn-percentage" = 85;
        label = "%used%";
        "label-warn" = "%used%";
      };

      # ── Right: Network ────────────────────────────────────────────────
      "module/net" = {
        type = "custom/script";
        exec = "/home/vino/.local/bin/bar-net";
        interval = 2;
      };

      # ── Right: Volume ─────────────────────────────────────────────────
      "module/vol" = {
        type = "internal/pulseaudio";
        sink = "@DEFAULT_SINK@";
        use-ui-max = false;
        interval = 5;
        format-volume = "${lb colors.base0D}<ramp-volume>%{F${colors.base05}}<label-volume>%{F-}${rb colors.base0D}";
        format-muted = "${lb colors.base08}%{F${colors.base08}}${icon "󰝟"} mute%{F-}${rb colors.base08}";
        label-volume = "%percentage%%";
        ramp-volume-0 = "%{F${colors.base02}}${icon "󰕿"} ";
        ramp-volume-1 = "%{F${colors.base0B}}${icon "󰖀"} ";
        ramp-volume-2 = "%{F${colors.base0B}}${icon "󰕾"} ";
        click-left = "${pactl} set-sink-mute @DEFAULT_SINK@ toggle";
        click-right = "pavucontrol &";
        scroll-up = "${pactl} set-sink-volume @DEFAULT_SINK@ +5%";
        scroll-down = "${pactl} set-sink-volume @DEFAULT_SINK@ -5%";
      };

      # ── Right: Battery ────────────────────────────────────────────────
      "module/bat" = {
        type = "custom/script";
        exec = "/home/vino/.local/bin/bar-bat";
        interval = 30;
        click-left = "/home/vino/.local/bin/bar-bat-cycle";
      };

      # ── Right: System tray ────────────────────────────────────────────
      "module/tray" = {
        type = "internal/tray";
        tray-spacing = "4px";
        tray-background = "\${colors.bg}";
        tray-padding = "2px";
      };
    };
  };

  home.file = {
    ".local/bin/bar-net" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        IP_CACHE="$XDG_RUNTIME_DIR/public-ip-cache"

        # Try to get cached IP first
        if [[ -r "$IP_CACHE" ]] && [[ $(find "$IP_CACHE" -mmin -10 -print 2>/dev/null) ]]; then
          IPV4=$(tr -d '[:space:]' < "$IP_CACHE")
        fi

        # If no cache or stale, fetch new IP
        if [[ -z "$IPV4" || "$IPV4" == "?.?.?.?" ]]; then
          IPV4=$(curl -s https://api.ipify.org 2>/dev/null || echo "?.?.?.?")
          # Cache the result
          echo "$IPV4" > "$IP_CACHE"
        fi

        IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
        if [[ -z "$IFACE" ]]; then
          echo "%{F${colors.base0C}}[%{F-} %{F${colors.base0C}}%{T2}󰓅%{T-} ''${IPV4}%{F-} %{F${colors.base0C}}]%{F-}%{F${colors.base02}}─%{F-}"
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

        echo "%{F${colors.base0C}}[%{F-} %{F${colors.base0C}}%{T2}''${ICON}%{T-} ''${IPV4}%{F-}%{F${colors.base0D}} · %{F-}%{F${colors.base0B}}↑''${DTX}k ↓''${DRX}k%{F-} %{F${colors.base0C}}]%{F-}%{F${colors.base02}}─%{F-}"
      '';
    };

    ".local/bin/bar-bat" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        BAT_DIR=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
        if [[ -z "$BAT_DIR" ]]; then
          echo "%{F${colors.base0E}}[%{F-} %{F${colors.base0E}}%{T3}${batteryIcon "󰾅"}%{T-} · %{T3}${batteryIcon "󰁽"}%{T-} ?%{F-} %{F${colors.base0E}}]%{F-}%{F${colors.base02}}─%{F-}"
          exit 0
        fi
        BAT=$(cat "$BAT_DIR/capacity" 2>/dev/null || echo "?")
        STATUS=$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")
        PROFILE=$(powerprofilesctl get 2>/dev/null || echo "balanced")
        case "''${PROFILE}" in
          performance) PI="󱐋"; PC="${colors.base08}" ;;
          power-saver) PI="󰌪"; PC="${colors.base0B}" ;;
          *)           PI="󰾅"; PC="${colors.base0A}" ;;
        esac
        if [[ "$STATUS" == "Charging" || "$STATUS" == "Full" ]]; then
          BI="󰂄"; BC="${colors.base0B}"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 10 ]]; then BI="󰁺"; BC="${colors.base08}"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 25 ]]; then BI="󰁻"; BC="${colors.base09}"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 50 ]]; then BI="󰁽"; BC="${colors.base0A}"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 75 ]]; then BI="󰁿"; BC="${colors.base0B}"
        else BI="󰂁"; BC="${colors.base0B}"; fi
        echo "%{F${colors.base0E}}[%{F-} %{F''${PC}}%{T3}''${PI}%{T-}%{F-}%{F${colors.base0D}} · %{F-}%{F''${BC}}%{T3}''${BI}%{T-} ''${BAT}%%{F-} %{F${colors.base0E}}]%{F-}%{F${colors.base02}}─%{F-}"
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
