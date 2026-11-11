{
  config,
  osConfig,
  pkgs,
  bandit,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  monospaceFont = config.stylix.fonts.monospace.name;
  kitty = "${pkgs.kitty}/bin/kitty";

  # Glyph in an accent colour, label stays in the bar's calm foreground.
  glyph = color: icon: "<span color='${color}'>${icon}</span>";
  # Same for markup built inside the scripts' single-quoted jq programs.
  jqGlyph = color: icon: ''<span color=\"${color}\">${icon}</span>'';

  # Failed systemd units (system + user) and journal errors since boot.
  barLogs = pkgs.writeShellApplication {
    name = "waybar-logs";
    runtimeInputs = [pkgs.jq pkgs.gawk pkgs.coreutils pkgs.gnused pkgs.gnugrep];
    text = ''
      failed=$( { systemctl --failed --no-legend --plain; systemctl --user --failed --no-legend --plain; } | awk '{print $1}')
      units=$(printf '%s' "$failed" | grep -c . || true)
      errors=$(journalctl -p err -b -q --no-pager -o cat | wc -l)
      recent=$(journalctl -p err -b -q --no-pager -n 5 -o short | sed -E 's/^(\S+ \S+ \S+) \S+ /\1 /' | cut -c1-110)
      if [ "$units" -gt 0 ]; then unit_color='${colors.base08}' class=failed; else unit_color='${colors.base0B}' class=ok; fi
      jq -cn --arg units "$units" --arg errors "$errors" --arg failed "$failed" --arg recent "$recent" \
        --arg uc "$unit_color" --arg class "$class" '
        def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
        {
          text: "<span color=\"\($uc)\">󰒓</span> \($units) ${jqGlyph colors.base03 "│"} <span color=\"${colors.base0A}\">󰀦</span> \($errors)",
          tooltip: ("Failed units: \($units)\n" + (if $failed == "" then "  none" else ($failed | esc | split("\n") | map("  " + .) | join("\n")) end)
            + "\n\nJournal errors this boot: \($errors)\n" + ($recent | esc)),
          class: $class
        }'
    '';
  };

  # Running docker (rootless) + podman containers; empty text hides the module.
  barContainers = pkgs.writeShellApplication {
    name = "waybar-containers";
    runtimeInputs = [pkgs.jq pkgs.coreutils pkgs.gnugrep];
    # docker/podman come from the system PATH so the CLI matches the daemon.
    text = ''
      names=""
      # Only ask docker when its daemon already runs, so the poll never starts it.
      if systemctl --user --quiet is-active docker.service && command -v docker >/dev/null; then
        names+=$(timeout 3 docker ps --format '󰡨 {{.Names}} ({{.Image}})' 2>/dev/null || true)$'\n'
      fi
      if command -v podman >/dev/null; then
        names+=$(timeout 3 podman ps --format '󰡨 {{.Names}} ({{.Image}}) [podman]' 2>/dev/null || true)
      fi
      names=$(printf '%s' "$names" | grep . || true)
      count=$(printf '%s' "$names" | grep -c . || true)
      if [ "$count" -eq 0 ]; then echo '{"text":""}'; exit 0; fi
      jq -cn --arg n "$count" --arg names "$names" '{
        text: "${jqGlyph colors.base0D "󰡨"} \($n)",
        tooltip: ($names | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;"))
      }'
    '';
  };

  # LAN (default-route interface) and Tailscale IPv4; `copy lan|ts` puts one on the clipboard.
  barIp = pkgs.writeShellApplication {
    name = "waybar-ip";
    runtimeInputs = [pkgs.jq pkgs.iproute2 pkgs.gawk pkgs.wl-clipboard pkgs.libnotify];
    text = ''
      v4() { ip -4 -o addr show dev "$1" 2>/dev/null | awk '{split($4, a, "/"); print a[1]; exit}'; }
      lan_dev=$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
      lan=""; [ -n "$lan_dev" ] && lan=$(v4 "$lan_dev")
      ts=$(v4 tailscale0)

      if [ "''${1:-}" = copy ]; then
        case "''${2:-}" in
          lan) ip=$lan label="LAN IP" ;;
          ts) ip=$ts label="Tailscale IP" ;;
          *) echo "usage: waybar-ip [copy lan|ts]" >&2; exit 2 ;;
        esac
        if [ -z "$ip" ]; then notify-send -t 2000 "$label" "no address"; exit 1; fi
        printf '%s' "$ip" | wl-copy
        notify-send -t 2000 "$label copied" "$ip"
        exit 0
      fi

      gw=$(ip -4 route show default | awk '{print $3 " (" $5 ")"; exit}')
      addrs=$(ip -o addr show | awk '$2 != "lo" {if ($2 != last) {printf "%s%s\n", (last != "" ? "\n" : ""), $2; last = $2} printf "  %s\n", $4}')
      jq -cn --arg lan "''${lan:---}" --arg ts "$ts" --arg addrs "$addrs" --arg gw "''${gw:-none}" '{
        text: ("${jqGlyph colors.base0C "󰩟"} \($lan) ${jqGlyph colors.base03 "│"} "
          + (if $ts == "" then "<span color=\"${colors.base08}\">󰖂 --</span>" else "${jqGlyph colors.base0C "󰖂"} \($ts)" end)),
        tooltip: ($addrs + "\ngateway \($gw)"),
        class: (if $ts == "" then "no-tailscale" else "ok" end)
      }'
    '';
  };
in {
  programs.waybar = {
    enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      # DepartureMono is drawn on an 11 px grid; 1.5x (16.5 px text, 33 px
      # bar) is the size that fits all modules in 2256 px. 2x (22 px) did not.
      height = 33;
      spacing = 0;
      margin-top = 0;
      margin-right = 0;
      margin-bottom = 0;
      margin-left = 0;

      modules-left = ["custom/host" "hyprland/workspaces" "hyprland/window"];
      modules-center = ["clock"];
      modules-right = [
        "privacy"
        "custom/logs"
        "custom/containers"
        "custom/ip"
        "network"
        "cpu"
        "memory"
        "group/system"
        "pulseaudio"
        "battery"
        "group/traydrawer"
      ];

      "custom/host" = {
        format = "󱄅 ${osConfig.networking.hostName}";
        on-click = "${config.programs.rofi.package}/bin/rofi -show drun";
        tooltip = false;
      };

      "hyprland/workspaces" = {
        # dwm style: only occupied workspaces and the active one.
        # Window icons at 11 px, DepartureMono's native size, so they stay sharp.
        format = "{icon}<span size='66.667%'> {windows}</span>";
        format-window-separator = " ";
        # Nerd Font Material Design glyphs; workspace layout in hyprland/rules.nix.
        format-icons = {
          "1" = "󰆍"; # U+F018D console
          "2" = "󰖟"; # U+F059F web
          "3" = "󰈙"; # U+F0219 file-document
          "4" = "󰊗"; # U+F0297 gamepad-variant
          "5" = "󰅩"; # U+F0169 code-braces
          "6" = "󰊌"; # U+F028C forum
          "7" = "󰉋"; # U+F024B folder
          "8" = "󰝚"; # U+F075A music
          "9" = "󰄜"; # U+F011C cellphone
          default = "󰇘"; # U+F01D8 dots-horizontal
        };
        window-rewrite-default = "󰣆";
        window-rewrite = {
          "class<kitty>" = "󰄛";
          "class<firefox>" = "󰈹";
          "class<brave-browser>" = "󰖟";
          "class<org.kde.okular>" = "󰈦";
          "class<obsidian>" = "󰠮";
          "class<libreoffice.*>" = "󰈬";
          "class<org.prismlauncher.PrismLauncher>" = "󰆧";
          "class<[Mm]inecraft.*>" = "󰍳";
          "class<thunderbird>" = "󰇮";
          "class<vesktop>" = "󰙯";
          "class<pcmanfm>" = "󰉋";
          "class<mpv>" = "󰎁";
          "class<.*scrcpy.*>" = "󰄜";
          "class<[Bb]itwarden>" = "󰌆";
          "class<.*pavucontrol>" = "󰕾";
        };
        on-click = "activate";
      };

      "hyprland/window" = {
        format = "{title}";
        max-length = 40;
        separate-outputs = true;
      };

      clock = {
        # Waybar's chrono format has no %^a; Pango uppercases instead.
        format = "<span text_transform='uppercase'>{:%a %d · %H:%M}</span>";
        interval = 10;
        tooltip-format = "<tt>{calendar}</tt>";
        calendar = {
          mode = "month";
          weeks-pos = "left";
          format = {
            months = "<span color='${colors.base05}'>{}</span>";
            days = "<span color='${colors.base04}'>{}</span>";
            weeks = "<span color='${colors.base03}'>W{}</span>";
            weekdays = "<span color='${colors.base0A}'>{}</span>";
            today = "<span color='${colors.base08}'><b>{}</b></span>";
          };
        };
      };

      privacy = {
        icon-size = 18;
        icon-spacing = 6;
        modules = [
          {type = "screenshare";}
          {type = "audio-in";}
        ];
      };

      "custom/logs" = {
        exec = "${barLogs}/bin/waybar-logs";
        return-type = "json";
        interval = 30;
        on-click = "${kitty} journalctl -p err -b -f";
        on-click-right = "${kitty} --hold sh -c 'systemctl --failed; systemctl --user --failed'";
      };

      "custom/containers" = {
        exec = "${barContainers}/bin/waybar-containers";
        return-type = "json";
        interval = 30;
      };

      "custom/ip" = {
        exec = "${barIp}/bin/waybar-ip";
        return-type = "json";
        interval = 15;
        on-click = "${barIp}/bin/waybar-ip copy lan";
        on-click-right = "${barIp}/bin/waybar-ip copy ts";
      };

      network = {
        format-wifi = "${glyph colors.base0B "󰖩"} {essid} ↓{bandwidthDownBytes} ↑{bandwidthUpBytes}";
        format-ethernet = "${glyph colors.base0B "󰈀"} {ifname} ↓{bandwidthDownBytes} ↑{bandwidthUpBytes}";
        format-linked = "${glyph colors.base0B "󰈀"} LINK";
        format-disconnected = "󰖪 OFF";
        tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ipaddr}/{cidr}";
        tooltip-format-ethernet = "{ifname}\n{ipaddr}/{cidr}";
        on-click = "${bandit.workstation.homeDirectory}/.local/bin/net-menu";
        interval = 5;
      };

      cpu = {
        # One sparkline bar per core (Framework 13: 12 threads).
        format = "${glyph colors.base0A "󰻠"} {icon0}{icon1}{icon2}{icon3}{icon4}{icon5}{icon6}{icon7}{icon8}{icon9}{icon10}{icon11} {usage}%";
        format-icons = ["▁" "▂" "▃" "▄" "▅" "▆" "▇" "█"];
        interval = 5;
        states = {
          warning = 70;
          critical = 90;
        };
        tooltip-format = "CPU load: {usage}%  ·  {avg_frequency} GHz";
      };

      memory = {
        format = "${glyph colors.base09 "󰍛"} {percentage}%";
        interval = 5;
        states = {
          warning = 70;
          critical = 90;
        };
        tooltip-format = "Memory: {used:0.1f} / {total:0.1f} GiB";
      };

      "group/system" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 200;
          transition-left-to-right = false;
          children-class = "drawer-child";
        };
        modules = ["power-profiles-daemon" "temperature" "disk"];
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

      temperature = {
        # k10temp Tctl by PCI path; hwmonN numbering changes between boots.
        hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
        input-filename = "temp1_input";
        critical-threshold = 85;
        interval = 10;
        format = "${glyph colors.base08 "󰔏"} {temperatureC}°C";
      };

      disk = {
        path = "/";
        interval = 120;
        format = "${glyph colors.base0F "󰋊"} {percentage_used}%";
        tooltip-format = "/ {used} of {total} ({free} free)";
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 MUTE";
        format-icons = {
          default = map (glyph colors.base0D) ["󰕿" "󰖀" "󰕾"];
        };
        on-click = "${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";
        on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
        on-scroll-up = "${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%";
        on-scroll-down = "${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%";
      };

      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{icon} {capacity}%";
        format-charging = "${glyph colors.base0B "󰂄"} {capacity}%";
        format-plugged = "${glyph colors.base0B "󰂄"} {capacity}%";
        format-full = "${glyph colors.base0B "󰁹"} {capacity}%";
        format-icons = map (glyph colors.base0E) ["󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
        tooltip-format = "{timeTo} · {power} W";
        interval = 30;
      };

      # Named traydrawer: a group called "tray" would share the tray's CSS id.
      "group/traydrawer" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 200;
          transition-left-to-right = false;
          children-class = "drawer-child";
        };
        modules = ["custom/tray-handle" "tray"];
      };

      "custom/tray-handle" = {
        format = "󰅁";
        tooltip = false;
      };

      tray = {
        spacing = 8;
        "icon-size" = 18;
      };
    };

    # Flat rail: edge-to-edge, no raised panels, shadows, or 3D effects.
    style = ''
      * {
        font-family: "DepartureMono Nerd Font", "${monospaceFont}";
        /* 1.5 x DepartureMono's 11 px grid; keep in sync with `height`.
           Regular only: a synthetic bold smears the pixel shapes. */
        font-size: 16.5px;
        font-weight: normal;
        border: none;
        border-radius: 0;
        box-shadow: none;
        text-shadow: none;
        transition: none;
        min-height: 0;
      }

      window#waybar {
        background-color: ${colors.base00};
        color: ${colors.base05};
        border-bottom: 1px solid ${colors.base02};
      }

      tooltip {
        color: ${colors.base05};
        background-color: ${colors.base01};
        border: 1px solid ${colors.base03};
      }

      tooltip label {
        padding: 4px 6px;
      }

      #custom-host,
      #window,
      #clock,
      #privacy,
      #custom-logs,
      #custom-containers,
      #custom-ip,
      #network,
      #cpu,
      #memory,
      #system,
      #pulseaudio,
      #battery,
      #traydrawer {
        margin: 0;
        padding: 0 8px;
        background-color: transparent;
        border-left: 1px solid ${colors.base02};
      }

      /* Drawer children sit inside their group's frame. */
      #power-profiles-daemon,
      #temperature,
      #disk,
      #custom-tray-handle,
      #tray {
        padding: 0 6px;
      }

      /* The retro signature: the six Apple stripes stacked on the left edge. */
      #custom-host {
        padding: 0 8px 0 14px;
        color: ${colors.base05};
        border-left: 0;
        background-image: linear-gradient(to bottom,
          ${colors.base0B} 0%, ${colors.base0B} 16.67%,
          ${colors.base0A} 16.67%, ${colors.base0A} 33.33%,
          ${colors.base09} 33.33%, ${colors.base09} 50%,
          ${colors.base08} 50%, ${colors.base08} 66.67%,
          ${colors.base0E} 66.67%, ${colors.base0E} 83.33%,
          ${colors.base0D} 83.33%, ${colors.base0D} 100%);
        background-size: 6px 100%;
        background-position: left;
        background-repeat: no-repeat;
      }

      #workspaces {
        margin: 0;
        padding: 0;
        border-left: 1px solid ${colors.base02};
      }

      #workspaces button {
        margin: 0;
        padding: 0 6px;
        color: ${colors.base04};
        background: transparent;
      }

      #workspaces button:hover {
        color: ${colors.base05};
        background: ${colors.base02};
      }

      /* Classic Mac menu highlight: inverted platinum. */
      #workspaces button.active {
        color: ${colors.base00};
        background: ${colors.base05};
      }

      #workspaces button.urgent {
        color: ${colors.base00};
        background: ${colors.base08};
      }

      #window {
        color: ${colors.base04};
      }

      #window.empty {
        padding: 0;
        border-left: 0;
      }

      #clock {
        padding: 0 16px;
        color: ${colors.base05};
        border-right: 1px solid ${colors.base02};
      }

      #privacy-item {
        padding: 0 4px;
      }

      #custom-logs.failed,
      #custom-ip.no-tailscale,
      #network.disconnected,
      #cpu.critical,
      #memory.critical,
      #temperature.critical,
      #battery.critical {
        color: ${colors.base08};
      }

      #cpu.warning,
      #memory.warning,
      #battery.warning {
        color: ${colors.base0A};
      }

      #cpu {
        color: ${colors.base04};
      }

      #pulseaudio.muted {
        color: ${colors.base03};
      }

      #power-profiles-daemon {
        color: ${colors.base0E};
      }

      #power-profiles-daemon.power-saver {
        color: ${colors.base0B};
      }

      #power-profiles-daemon.performance {
        color: ${colors.base09};
      }

      #custom-tray-handle {
        color: ${colors.base04};
      }

      #tray > .passive {
        -gtk-icon-effect: dim;
      }
    '';

    systemd.enable = true;
  };

  home.packages = [pkgs.pavucontrol pkgs.nerd-fonts.departure-mono];
}
