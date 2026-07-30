{
  config,
  pkgs,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  monospaceFont = config.stylix.fonts.monospace.name;
in {
  programs.waybar = {
    enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      # Framework 13's 2256x1504 panel runs at scale 1, so keep the bar
      # tall enough to read comfortably; font-size below tracks this.
      height = 44;
      spacing = 0;
      margin-top = 0;
      margin-right = 0;
      margin-bottom = 0;
      margin-left = 0;

      modules-left = ["custom/nix" "hyprland/workspaces" "hyprland/window"];
      modules-center = ["clock"];
      modules-right = [
        "cpu"
        "memory"
        "network"
        "pulseaudio"
        "power-profiles-daemon"
        "battery"
        "tray"
      ];

      "custom/nix" = {
        format = "󱄅 BANDIT";
        on-click = "${pkgs.rofi}/bin/rofi -show drun";
        tooltip = false;
      };

      "hyprland/workspaces" = {
        format = "{id}";
        on-click = "activate";
      };

      "hyprland/window" = {
        format = "󰣆  {title}";
        max-length = 48;
        separate-outputs = true;
        rewrite = {
          "^$" = "DESKTOP";
        };
      };

      clock = {
        format = "{:%a %d  ▪  %H:%M}";
        interval = 10;
        tooltip-format = "{:%Y-%m-%d %H:%M:%S}";
      };

      cpu = {
        format = "󰻠 {usage}%";
        interval = 2;
        states = {
          warning = 70;
          critical = 90;
        };
        tooltip-format = "CPU load: {usage}%";
      };

      memory = {
        format = "󰍛 {percentage}%";
        interval = 3;
        states = {
          warning = 70;
          critical = 90;
        };
        tooltip-format = "Memory: {used:0.1f} / {total:0.1f} GiB";
      };

      network = {
        format-wifi = "󰖩 {signalStrength}%";
        format-ethernet = "󰈀 {ifname}";
        format-linked = "󰈀 LINK";
        format-disconnected = "󰖪 OFF";
        tooltip-format-wifi = "{essid}\n{ipaddr}/{cidr}\n⇣ {bandwidthDownBytes}  ⇡ {bandwidthUpBytes}";
        tooltip-format-ethernet = "{ifname}\n{ipaddr}/{cidr}\n⇣ {bandwidthDownBytes}  ⇡ {bandwidthUpBytes}";
        interval = 2;
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 MUTE";
        format-icons = {
          default = ["󰕿" "󰖀" "󰕾"];
        };
        on-click = "${pkgs.pipewire}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";
        on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
        on-scroll-up = "${pkgs.pipewire}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%";
        on-scroll-down = "${pkgs.pipewire}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%";
      };

      "power-profiles-daemon" = {
        format = "{icon}";
        tooltip-format = "Power profile: {profile}";
        format-icons = {
          default = "󰾅";
          performance = "󱐋";
          balanced = "󰾅";
          power-saver = "󰌪";
        };
      };

      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-plugged = "󰂄 {capacity}%";
        format-full = "󰁹 {capacity}%";
        format-icons = ["󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
        tooltip-format = "{timeTo} · {power} W";
        interval = 30;
      };

      tray = {
        spacing = 6;
        "icon-size" = 18;
      };
    };

    # Flat Gruvbox rail: edge-to-edge, compact, and colorful without raised
    # panels, shadows, or other three-dimensional effects.
    style = ''
      * {
        font-family: "${monospaceFont}";
        /* Slightly larger than the old 14px so module text stays legible
           at the panel's native resolution; keep in sync with `height`. */
        font-size: 16px;
        font-weight: bold;
        font-feature-settings: "tnum";
        border: none;
        border-radius: 0;
        box-shadow: none;
        text-shadow: none;
        transition: none;
        min-height: 0;
      }

      window#waybar {
        background-color: ${colors.base01};
        color: ${colors.base05};
        border-bottom: 2px solid ${colors.base03};
        box-shadow: none;
      }

      tooltip {
        color: ${colors.base05};
        background-color: ${colors.base01};
        border: 1px solid ${colors.base03};
        box-shadow: none;
      }

      tooltip label {
        padding: 4px 6px;
      }

      #custom-nix,
      #window,
      #clock,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #power-profiles-daemon,
      #battery,
      #tray {
        margin: 0;
        padding: 0 7px;
        background-color: transparent;
        border-left: 1px solid ${colors.base02};
        box-shadow: none;
      }

      #custom-nix {
        padding-left: 9px;
        color: ${colors.base05};
        border-left: 0;
      }

      #workspaces {
        margin: 0;
        padding: 0;
        background-color: transparent;
        border-left: 1px solid ${colors.base02};
      }

      #workspaces button {
        min-width: 34px;
        margin: 0;
        padding: 0 6px;
        color: ${colors.base04};
        background: transparent;
        border: 0;
        border-bottom: 2px solid transparent;
        box-shadow: none;
        text-shadow: none;
      }

      #workspaces button:hover {
        color: ${colors.base05};
        background-color: ${colors.base02};
        box-shadow: none;
      }

      #workspaces button.active {
        color: ${colors.base05};
        background-color: transparent;
        border-bottom-color: ${colors.base03};
      }

      #workspaces button.urgent {
        color: ${colors.base08};
        background-color: transparent;
        border-bottom-color: ${colors.base08};
      }

      #window {
        color: ${colors.base04};
      }

      #window.empty {
        padding: 0;
      }

      #clock {
        padding: 0 12px;
        color: ${colors.base05};
        border-right: 1px solid ${colors.base02};
      }

      #cpu {
        color: ${colors.base0C};
      }

      #memory {
        color: ${colors.base0A};
      }

      #cpu.warning,
      #memory.warning {
        color: ${colors.base0E};
      }

      #cpu.critical,
      #memory.critical {
        color: ${colors.base08};
      }

      #network {
        color: ${colors.base0B};
      }

      #network.disconnected {
        color: ${colors.base08};
      }

      #pulseaudio {
        color: ${colors.base0D};
      }

      #pulseaudio.muted {
        color: ${colors.base04};
      }

      #power-profiles-daemon {
        color: ${colors.base0E};
      }

      #power-profiles-daemon.power-saver {
        color: ${colors.base0B};
      }

      #power-profiles-daemon.performance {
        color: ${colors.base08};
      }

      #battery {
        color: ${colors.base0E};
      }

      #battery.charging,
      #battery.plugged,
      #battery.full {
        color: ${colors.base0B};
      }

      #battery.warning {
        color: ${colors.base0A};
      }

      #battery.critical {
        color: ${colors.base08};
      }

      #tray {
        padding-right: 9px;
      }

      #tray > .passive {
        -gtk-icon-effect: dim;
      }
    '';

    systemd.enable = true;
  };

  home.packages = [pkgs.pavucontrol];
}
