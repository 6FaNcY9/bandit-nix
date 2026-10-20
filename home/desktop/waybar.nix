{
  config,
  pkgs,
  ...
}: let
  r = config.bandit.theme.roles;
  monospaceFont = config.stylix.fonts.monospace.name;

  # dev/ops indicator: reads the state written by `ops on` (home/terminal/ops.nix).
  # Dev mode prints an empty text, which waybar hides.
  modeStatus = pkgs.writeShellApplication {
    name = "bandit-mode-status";
    runtimeInputs = [pkgs.coreutils pkgs.gnused pkgs.jq];
    text = ''
      modefile="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bandit/mode"
      if [ ! -f "$modefile" ]; then
        jq -cn '{text: "", class: "dev", tooltip: ""}'
        exit 0
      fi
      get() { sed -n "s/^$1=//p" "$modefile" | head -1; }
      jq -cn --arg n "$(get name)" --arg p "$(get path)" --arg s "$(get since)" \
        '{text: ("OPS " + $n), class: "ops", tooltip: ($p + "\nsince " + $s)}'
    '';
  };
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

      modules-left = ["custom/nix" "custom/mode" "hyprland/workspaces" "hyprland/window"];
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
        on-click = "${config.programs.rofi.package}/bin/rofi -show drun";
        tooltip = false;
      };

      "custom/mode" = {
        exec = "${modeStatus}/bin/bandit-mode-status";
        return-type = "json";
        interval = "once";
        # `ops on|off` sends SIGRTMIN+8.
        signal = 8;
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
        interval = 30;
        tooltip-format = "{:%Y-%m-%d %H:%M}";
      };

      cpu = {
        format = "󰻠 {usage}%";
        interval = 5;
        states = {
          warning = 70;
          critical = 90;
        };
        tooltip-format = "CPU load: {usage}%";
      };

      memory = {
        format = "󰍛 {percentage}%";
        interval = 10;
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
        on-click = "${config.home.file.".local/bin/net-menu".source}";
        interval = 5;
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 MUTE";
        format-icons = {
          default = ["󰕿" "󰖀" "󰕾"];
        };
        on-click = "${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";
        on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
        on-scroll-up = "${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%";
        on-scroll-down = "${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%";
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

    # Flat ops-console rail: edge-to-edge, square, 1px structure lines; text in
    # the grey ramp, accents only for state (see themes/palette.nix roles).
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
        background-color: ${r.surface};
        color: ${r.fg};
        border-bottom: 1px solid ${r.line};
        box-shadow: none;
      }

      tooltip {
        color: ${r.fg};
        background-color: ${r.surface};
        border: 1px solid ${r.line};
        border-radius: 0;
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
        color: ${r.fg};
        background-color: transparent;
        border-left: 1px solid ${r.line};
        box-shadow: none;
      }

      #custom-nix {
        padding-left: 9px;
        border-left: 0;
      }

      #workspaces {
        margin: 0;
        padding: 0;
        background-color: transparent;
        border-left: 1px solid ${r.line};
      }

      #workspaces button {
        min-width: 34px;
        margin: 0;
        padding: 0 6px;
        color: ${r.dim};
        background: transparent;
        border: 0;
        box-shadow: none;
        text-shadow: none;
      }

      #workspaces button:hover {
        color: ${r.fg};
        background-color: ${r.raised};
        box-shadow: none;
      }

      #workspaces button.active {
        color: ${r.bg};
        background-color: ${r.accent};
      }

      #workspaces button.urgent {
        color: ${r.bg};
        background-color: ${r.crit};
      }

      /* Engagement active: the only place the ops role is used in the bar. */
      #custom-mode.ops {
        margin: 0;
        padding: 0 7px;
        color: ${r.ops};
        background-color: transparent;
        border-left: 1px solid ${r.ops};
        border-right: 1px solid ${r.ops};
      }

      #custom-mode.dev {
        padding: 0;
        border: 0;
      }

      #window {
        color: ${r.dim};
      }

      #window.empty {
        padding: 0;
      }

      #clock {
        padding: 0 12px;
        border-right: 1px solid ${r.line};
      }

      #cpu.warning,
      #memory.warning {
        color: ${r.warn};
      }

      #cpu.critical,
      #memory.critical {
        color: ${r.crit};
      }

      #network {
        color: ${r.ok};
      }

      #network.disconnected {
        color: ${r.muted};
      }

      #pulseaudio.muted {
        color: ${r.muted};
      }

      #power-profiles-daemon.power-saver {
        color: ${r.ok};
      }

      #power-profiles-daemon.performance {
        color: ${r.warn};
      }

      #battery.charging,
      #battery.plugged,
      #battery.full {
        color: ${r.ok};
      }

      #battery.warning {
        color: ${r.warn};
      }

      #battery.critical {
        color: ${r.crit};
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
