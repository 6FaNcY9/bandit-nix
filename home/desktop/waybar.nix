{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  localBin = "${repoConfig.workstation.homeDirectory}/.local/bin";
in {
  programs.waybar = {
    enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 38;
      spacing = 0;

      modules-left = ["custom/nix" "hyprland/workspaces"];
      modules-center = ["clock"];
      modules-right = ["cpu" "memory" "custom/net" "pulseaudio" "custom/battery" "tray"];

      "custom/nix" = {
        format = "󱄅 bandit";
        on-click = "${pkgs.rofi}/bin/rofi -show drun";
        tooltip = false;
      };

      "hyprland/workspaces" = {
        format = "{id}";
        on-click = "activate";
      };

      clock = {
        format = "{:%a %d  %H:%M}";
        interval = 10;
        tooltip-format = "{:%Y-%m-%d %H:%M:%S}";
      };

      cpu = {
        format = "󰻠 {usage}%";
        interval = 2;
      };

      memory = {
        format = "󰍛 {percentage}%";
        interval = 3;
      };

      "custom/net" = {
        exec = "${localBin}/bar-net";
        return-type = "json";
        interval = 15;
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 mute";
        format-icons = {
          default = ["󰕿" "󰖀" "󰕾"];
        };
        on-click = "${pkgs.pipewire}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";
        on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
        on-scroll-up = "${pkgs.pipewire}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%";
        on-scroll-down = "${pkgs.pipewire}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%";
      };

      "custom/battery" = {
        exec = "${localBin}/bar-bat";
        return-type = "json";
        interval = 30;
        on-click = "${localBin}/bar-bat-cycle";
      };

      tray = {
        spacing = 8;
        "icon-size" = 18;
      };
    };

    # Retro bracket-and-rail look, carried over from the old Polybar config:
    # every module reads as "[ content ]" with a dim connecting rail between
    # groups, brackets in a muted tone and content in the module's accent.
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font Mono";
        font-size: 13px;
        font-weight: bold;
        border-radius: 0;
        transition: none;
      }

      window#waybar {
        background-color: ${colors.base00};
        color: ${colors.base05};
        border-bottom: 1px solid ${colors.base02};
      }

      #workspaces,
      #custom-nix,
      #clock,
      #cpu,
      #memory,
      #custom-net,
      #pulseaudio,
      #custom-battery,
      #tray {
        margin: 0 2px;
      }

      #custom-nix,
      #clock,
      #cpu,
      #memory,
      #custom-net,
      #pulseaudio,
      #custom-battery {
        padding: 0 10px;
      }

      #custom-nix::before,
      #clock::before,
      #cpu::before,
      #memory::before,
      #custom-net::before,
      #pulseaudio::before,
      #custom-battery::before {
        content: "[ ";
        color: ${colors.base02};
      }
      #custom-nix::after,
      #clock::after,
      #cpu::after,
      #memory::after,
      #custom-net::after,
      #pulseaudio::after,
      #custom-battery::after {
        content: " ]";
        color: ${colors.base02};
      }

      #custom-nix { color: ${colors.base0D}; }

      #workspaces button {
        padding: 0 6px;
        color: ${colors.base03};
        background: transparent;
      }
      #workspaces button::before { content: "["; color: ${colors.base02}; padding-right: 3px; }
      #workspaces button::after { content: "]"; color: ${colors.base02}; padding-left: 3px; }

      #workspaces button.active {
        color: ${colors.base0A};
      }

      #workspaces button.urgent {
        color: ${colors.base08};
      }

      #clock { color: ${colors.base0A}; }
      #cpu { color: ${colors.base0B}; }
      #memory { color: ${colors.base09}; }
      #custom-net { color: ${colors.base0C}; }
      #pulseaudio { color: ${colors.base0D}; }
      #custom-battery { color: ${colors.base0E}; }
      #custom-battery.critical { color: ${colors.base08}; }

      #tray {
        background-color: ${colors.base00};
        padding: 0 10px;
      }
    '';

    systemd.enable = true;
  };

  home.file = {
    ".local/bin/bar-net" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        set -uo pipefail
        IP_CACHE="$XDG_RUNTIME_DIR/public-ip-cache"

        if [[ -r "$IP_CACHE" ]] && [[ $(find "$IP_CACHE" -mmin -10 -print 2>/dev/null) ]]; then
          IPV4=$(tr -d '[:space:]' < "$IP_CACHE")
        fi

        if [[ -z "''${IPV4:-}" || "$IPV4" == "?.?.?.?" ]]; then
          IPV4=$(curl -s https://api.ipify.org 2>/dev/null || echo "?.?.?.?")
          echo "$IPV4" > "$IP_CACHE"
        fi

        IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
        if [[ -z "$IFACE" ]]; then
          printf '{"text": "󰈀 %s", "tooltip": "no default route"}\n' "$IPV4"
          exit 0
        fi

        [[ -d "/sys/class/net/''${IFACE}/wireless" ]] && ICON="󰖩" || ICON="󰈀"

        PREV="$XDG_RUNTIME_DIR/bar-net-prev-$IFACE"
        read -r prev_rx prev_tx < "$PREV" 2>/dev/null || true
        RX=$(awk -v i="$IFACE:" '$1==i {print $2}' /proc/net/dev)
        TX=$(awk -v i="$IFACE:" '$1==i {print $10}' /proc/net/dev)
        echo "$RX $TX" > "$PREV"
        if [[ -n "''${prev_rx:-}" && "$RX" -ge "$prev_rx" && "$TX" -ge "$prev_tx" ]]; then
          DRX=$(( (RX - prev_rx) / 1024 ))
          DTX=$(( (TX - prev_tx) / 1024 ))
        else
          DRX=0; DTX=0
        fi

        printf '{"text": "%s %s  ↑%sk ↓%sk", "tooltip": "%s"}\n' "$ICON" "$IPV4" "$DTX" "$DRX" "$IFACE"
      '';
    };

    ".local/bin/bar-bat" = {
      executable = true;
      text = ''
        #!${pkgs.bash}/bin/bash
        set -uo pipefail
        BAT_DIR=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
        if [[ -z "$BAT_DIR" ]]; then
          printf '{"text": "󰾅 no battery", "class": "normal"}\n'
          exit 0
        fi
        BAT=$(cat "$BAT_DIR/capacity" 2>/dev/null || echo "?")
        STATUS=$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")
        PROFILE=$(powerprofilesctl get 2>/dev/null || echo "balanced")
        case "$PROFILE" in
          performance) PI="󱐋" ;;
          power-saver) PI="󰌪" ;;
          *)           PI="󰾅" ;;
        esac
        if [[ "$STATUS" == "Charging" || "$STATUS" == "Full" ]]; then
          BI="󰂄"; CLASS="normal"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 15 ]]; then BI="󰁺"; CLASS="critical"
        elif [[ "$BAT" =~ ^[0-9]+$ && "$BAT" -le 50 ]]; then BI="󰁽"; CLASS="normal"
        else BI="󰂁"; CLASS="normal"; fi
        printf '{"text": "%s  %s %s%%", "class": "%s"}\n' "$PI" "$BI" "$BAT" "$CLASS"
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
