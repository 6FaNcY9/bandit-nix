{
  config,
  osConfig,
  pkgs,
  bandit,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  barFont = config.stylix.fonts.monospace.name;
  barSize = config.stylix.fonts.sizes.desktop;
  kitty = "${pkgs.kitty}/bin/kitty";

  # Bluetooth menu in the same rofi look as the other menus.
  btMenu = pkgs.writeShellScript "bt-menu" ''
    PATH=${config.programs.rofi.package}/bin:$PATH
    exec ${pkgs.rofi-bluetooth}/bin/rofi-bluetooth -theme retro-eighties
  '';

  # Health line: failed units (system + user), else journal errors of the last 15 minutes.
  barLogs = pkgs.writeShellApplication {
    name = "waybar-logs";
    runtimeInputs = [pkgs.jq pkgs.gawk pkgs.coreutils pkgs.gnused pkgs.gnugrep];
    text = ''
      # A hung or failing systemd/journal call must not hang the bar or read as "all quiet":
      # fail() records which call broke (124 is timeout's exit status) and the bar shows "health ?".
      bad=""
      fail() {
        local rc=$?
        if [ "$rc" -eq 124 ]; then bad+="$1 timed out"$'\n'; else bad+="$1 failed (exit $rc)"$'\n'; fi
      }
      sys=$(timeout 5 systemctl --failed --no-legend --plain) || { fail "systemctl"; sys=""; }
      usr=$(timeout 5 systemctl --user --failed --no-legend --plain) || { fail "systemctl --user"; usr=""; }
      errs=$(timeout 5 journalctl -p err --since -15min -q --no-pager -o cat) || { fail "journalctl (15 min)"; errs=""; }
      last=$(timeout 5 journalctl -p err -b -q --no-pager -n 200 -o short) || { fail "journalctl (this boot)"; last=""; }
      # dbus-broker logs this as an error for every service file on each switch; it is harmless.
      noise="Ignoring duplicate name '"
      errs=$(grep -vF "$noise" <<<"$errs" || true)
      last=$(grep -vF "$noise" <<<"$last" | tail -n 5 || true)
      failed=$(printf '%s\n%s\n' "$sys" "$usr" | awk 'NF {print $1}')
      units=$(printf '%s' "$failed" | grep -c . || true)
      errors=$(printf '%s' "$errs" | grep -c . || true)
      recent=$(printf '%s' "$last" | sed -E 's/^(\S+ \S+ \S+) \S+ /\1 /' | cut -c1-110)
      if [ "$units" -gt 0 ]; then
        class=failed text="$units FAILED · $(awk 'NR == 1' <<<"$failed")"
      elif [ "$errors" -gt 0 ]; then
        class=warn text="$errors ERR 15m"
      elif [ -n "$bad" ]; then
        class=warn text="health ?"
      else
        class=ok text="all quiet"
      fi
      jq -cn --arg text "$text" --arg class "$class" --arg units "$units" --arg errors "$errors" \
        --arg failed "$failed" --arg recent "$recent" --arg bad "$bad" '
        def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
        {
          text: ($text | esc),
          tooltip: ("Failed units: \($units)\n" + (if $failed == "" then "  none" else ($failed | esc | split("\n") | map("  " + .) | join("\n")) end)
            + "\n\nJournal errors, last 15 min: \($errors)\n\nLast errors this boot:\n" + ($recent | esc)
            + (if $bad == "" then "" else "\n\nHealth check incomplete:\n" + ($bad | rtrimstr("\n") | esc | split("\n") | map("  " + .) | join("\n")) end)),
          class: $class
        }'
    '';
  };

  # Stream mode (hides IPs and the hostname, mutes mako). The wrappers that mask call it, so it must be in their runtimeInputs:
  # a missing waybar-stream would silently leave the IPs visible.
  barStream = pkgs.writeShellApplication {
    name = "waybar-stream";
    runtimeInputs = [pkgs.coreutils pkgs.mako pkgs.procps];
    text = builtins.readFile ../../../tools/waybar-stream.sh;
  };

  # MIC while an app records audio, SCREEN while a screen share runs; empty text hides the module.
  barPrivacy = pkgs.writeShellApplication {
    name = "waybar-privacy";
    runtimeInputs = [pkgs.pipewire pkgs.jq pkgs.coreutils barStream];
    text = ''
      screen=""
      while true; do
        if items=$(timeout 5 pw-dump 2>/dev/null | jq -r '
          [.[] | select(.type == "PipeWire:Interface:Node" and .info.state == "running") | .info.props] as $n
          | [ (if any($n[]; .["media.class"] == "Stream/Input/Audio") then "MIC" else empty end),
              (if any($n[]; .["media.class"] == "Video/Source" and ((.["node.name"] // "") | startswith("xdph"))) then "SCREEN" else empty end) ]
          | join(" ")
        '); then
          case " $items " in *" SCREEN "*) now=on ;; *) now=off ;; esac
          # Every waybar-stream call signals Waybar, so call it only when the share starts or stops (the first pass counts as a change).
          if [ "$now" != "$screen" ]; then screen=$now; waybar-stream auto "$now" || true; fi
        else
          items="" # pw-dump failed: hide the module, keep the last share state
        fi
        # A manual toggle without a share stays visible on the bar.
        if waybar-stream status; then items="''${items:+$items }STREAM"; fi
        if [ -n "$items" ]; then jq -cn --arg t "$items" '{text: $t, class: "active"}'; else echo '{"text":""}'; fi
        sleep 3
      done
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
        names+=$(timeout 3 docker ps --format '{{.Names}} ({{.Image}})' 2>/dev/null || true)$'\n'
      fi
      if command -v podman >/dev/null; then
        names+=$(timeout 3 podman ps --format '{{.Names}} ({{.Image}}) [podman]' 2>/dev/null || true)
      fi
      names=$(printf '%s' "$names" | grep . || true)
      count=$(printf '%s' "$names" | grep -c . || true)
      if [ "$count" -eq 0 ]; then echo '{"text":""}'; exit 0; fi
      jq -cn --arg n "$count" --arg names "$names" '{
        text: "CTR \($n)",
        tooltip: ($names | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;"))
      }'
    '';
  };

  # LAN (default-route interface) and Tailscale IPv4; `copy lan|ts` puts one on the clipboard.
  barIp = pkgs.writeShellApplication {
    name = "waybar-ip";
    runtimeInputs = [pkgs.jq pkgs.iproute2 pkgs.gawk pkgs.wl-clipboard pkgs.libnotify barStream];
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
        # the clipboard gets the real IP, the notification must not show it on stream
        shown=$ip; if waybar-stream status; then shown=•••; fi
        notify-send -t 2000 "$label copied" "$shown"
        exit 0
      fi

      if waybar-stream status; then
        echo '{"text":"LAN ••• │ TS •••","tooltip":"•••"}'
        exit 0
      fi

      gw=$(ip -4 route show default | awk '{print $3 " (" $5 ")"; exit}')
      addrs=$(ip -o addr show | awk '$2 != "lo" {if ($2 != last) {printf "%s%s\n", (last != "" ? "\n" : ""), $2; last = $2} printf "  %s\n", $4}')
      jq -cn --arg lan "''${lan:---}" --arg ts "$ts" --arg addrs "$addrs" --arg gw "''${gw:-none}" '{
        text: "LAN \($lan) │ TS \(if $ts == "" then "--" else $ts end)",
        tooltip: ($addrs + "\ngateway \($gw)"),
        class: (if $ts == "" then "no-tailscale" else "ok" end)
      }'
    '';
  };

  # Claude weekly limit from the claude-hud usage snapshot (its config.json points externalUsageWritePath there).
  barAi = pkgs.writeShellApplication {
    name = "waybar-ai";
    runtimeInputs = [pkgs.jq pkgs.coreutils];
    text = "BAR_AI_FILE='${config.xdg.cacheHome}/claude-hud/usage.json'\n" + builtins.readFile ../../../tools/waybar-ai.sh;
  };

  # VPN IP -> pt target; `copy target|vpn` for the clicks.
  barTarget = pkgs.writeShellApplication {
    name = "waybar-target";
    runtimeInputs = [pkgs.coreutils pkgs.gnused pkgs.jq pkgs.iproute2 pkgs.wl-clipboard pkgs.libnotify barStream];
    text = "BAR_PENTEST_SESSION='${config.home.homeDirectory}/src/sec/.pentest-session' BAR_GREEN='${colors.base0B}' BAR_RED='${colors.base08}'\n" + builtins.readFile ../../../tools/waybar-target.sh;
  };

  # Shield: does the lab's ad-blocking DNS answer while the laptop is on the tailnet? Display only.
  barDns = pkgs.writeShellApplication {
    name = "waybar-dns";
    runtimeInputs = [pkgs.iproute2 pkgs.jq pkgs.coreutils pkgs.getent];
    text = builtins.readFile ../../../tools/waybar-dns.sh;
  };

  # Installed by scripts.nix; same route as net-menu.
  lage = "${bandit.workstation.homeDirectory}/.local/bin/lage";
in {
  programs.waybar = {
    enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      # Text is Stylix's desktop size (pt); the bar is twice the text height.
      height = builtins.floor (barSize * 4 / 3 * 2);
      spacing = 0;
      margin-top = 0;
      margin-right = 0;
      margin-bottom = 0;
      margin-left = 0;

      modules-left = ["custom/host" "hyprland/workspaces"];
      modules-center = ["clock"];
      modules-right = ["custom/agents" "custom/ai"];

      "custom/host" = {
        # An exec module so stream mode can hide the hostname; signal 8 redraws it at once.
        exec = "${barStream}/bin/waybar-stream text ${osConfig.networking.hostName}";
        return-type = "json";
        interval = 5; # fallback if the signal is missed
        signal = 8;
        on-click = "${config.programs.rofi.package}/bin/rofi -show drun";
        tooltip = false;
      };

      # Busy and waiting Claude sessions, counted by lage like its pane; click focuses the waiting one.
      "custom/agents" = {
        exec = "${lage} bar";
        return-type = "json";
        interval = 5;
        # The tooltip carries tool lines that may hold < and &; escape also covers the tooltip.
        escape = true;
        on-click = "${lage} bar --focus";
      };

      "custom/ai" = {
        exec = "${barAi}/bin/waybar-ai";
        return-type = "json";
        interval = 30;
      };

      "hyprland/workspaces" = {
        # dwm style: only occupied workspaces and the active one.
        format = "{icon}";
        # Layout in hyprland/rules.nix.
        format-icons = {
          "1" = "1 term";
          "2" = "2 web";
          "3" = "3 doc";
          "4" = "4 game";
          "5" = "5 code";
          "6" = "6 chat";
          "7" = "7 files";
          "8" = "8 music";
          "9" = "9 phone";
          default = "+";
        };
        on-click = "activate";
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
            weekdays = "<span color='${colors.base04}'>{}</span>";
            today = "<span color='${colors.base08}'><b>{}</b></span>";
          };
        };
      };
    };

    settings.bottomBar = {
      layer = "top";
      position = "bottom";
      # 1.75x the text height, a little slimmer than the top bar.
      height = builtins.floor (barSize * 4 / 3 * 1.75);
      spacing = 0;
      margin-top = 0;
      margin-right = 0;
      margin-bottom = 0;
      margin-left = 0;

      modules-left = ["group/admin" "custom/target"];
      modules-right = ["custom/privacy" "custom/dns" "network" "group/system" "pulseaudio" "bluetooth" "battery" "group/traydrawer"];

      "custom/privacy" = {
        exec = "${barPrivacy}/bin/waybar-privacy";
        return-type = "json";
        tooltip = false;
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
        signal = 8;
      };

      "custom/target" = {
        exec = "${barTarget}/bin/waybar-target";
        return-type = "json";
        interval = 5;
        signal = 8;
        on-click = "${barTarget}/bin/waybar-target copy target";
        on-click-right = "${barTarget}/bin/waybar-target copy vpn";
      };

      "custom/dns" = {
        exec = "${barDns}/bin/waybar-dns";
        return-type = "json";
        interval = 60;
      };

      network = {
        # Network name lives in the tooltip; the bar keeps the traffic.
        format-wifi = "󰖩 ↓{bandwidthDownBytes} ↑{bandwidthUpBytes}";
        format-ethernet = "󰈀 {ifname} ↓{bandwidthDownBytes} ↑{bandwidthUpBytes}";
        format-linked = "󰈀 LINK";
        format-disconnected = "󰖪 OFF";
        tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ipaddr}/{cidr}";
        tooltip-format-ethernet = "{ifname}\n{ipaddr}/{cidr}";
        on-click = "${bandit.workstation.homeDirectory}/.local/bin/net-menu";
        interval = 5;
      };

      cpu = {
        # Total load only: the per-core sparkline no longer fits at the larger size.
        format = "CPU {usage}%";
        interval = 5;
        states = {
          warning = 70;
          critical = 90;
        };
        tooltip-format = "CPU load: {usage}%  ·  {avg_frequency} GHz";
      };

      memory = {
        format = "MEM {percentage}%";
        interval = 5;
        states = {
          warning = 70;
          critical = 90;
        };
        tooltip-format = "Memory: {used:0.1f} / {total:0.1f} GiB";
      };

      # Errors stay visible; IPs and containers open on hover (room for the larger text).
      "group/admin" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 200;
          transition-left-to-right = true;
          children-class = "drawer-child";
        };
        modules = ["custom/logs" "custom/ip" "custom/containers"];
      };

      "group/system" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 200;
          transition-left-to-right = false;
          children-class = "drawer-child";
        };
        # CPU stays visible; memory, temperature, disk and power profile on hover.
        modules = ["cpu" "memory" "temperature" "disk" "power-profiles-daemon"];
      };

      "power-profiles-daemon" = {
        format = "PWR {icon}";
        tooltip-format = "Power profile: {profile}";
        format-icons = {
          default = "bal";
          performance = "perf";
          balanced = "bal";
          power-saver = "save";
        };
      };

      temperature = {
        # k10temp Tctl by PCI path; hwmonN numbering changes between boots.
        hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
        input-filename = "temp1_input";
        critical-threshold = 85;
        interval = 10;
        format = "TEMP {temperatureC}°C";
      };

      disk = {
        path = "/";
        interval = 120;
        format = "DISK {percentage_used}%";
        tooltip-format = "/ {used} of {total} ({free} free)";
      };

      pulseaudio = {
        format = "VOL {volume}%";
        format-muted = "VOL MUTE";
        on-click = "${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";
        on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
        on-scroll-up = "${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%";
        on-scroll-down = "${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%";
      };

      # State word (+ headset battery) only; device names in the tooltip.
      bluetooth = {
        format = "BT";
        format-off = "BT OFF";
        format-disabled = "BT OFF";
        format-connected = "BT ON";
        format-connected-battery = "BT {device_battery_percentage}%";
        tooltip-format = "Bluetooth: {status}";
        tooltip-format-connected = "{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}";
        tooltip-format-enumerate-connected-battery = "{device_alias} {device_battery_percentage}%";
        # Full device list + pairing in a terminal TUI; quick connect via rofi.
        on-click = "${kitty} --class bluetui -e ${pkgs.bluetui}/bin/bluetui";
        on-click-right = "${btMenu}";
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
        format = "&lt;";
        tooltip = false;
      };

      tray = {
        spacing = 8;
        "icon-size" = builtins.floor (barSize * 4 / 3);
      };
    };

    # Flat rail: edge-to-edge, no raised panels, shadows, or 3D effects.
    style = ''
      * {
        font-family: "${barFont}";
        font-size: ${toString barSize}pt;
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
      }

      window#waybar.top {
        border-bottom: 1px solid ${colors.base02};
      }

      window#waybar.bottom {
        border-top: 1px solid ${colors.base02};
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
      #custom-agents,
      #custom-ai,
      #clock,
      #custom-privacy,
      #custom-target,
      #custom-dns,
      #admin,
      #network,
      #system,
      #pulseaudio,
      #bluetooth,
      #battery,
      #traydrawer {
        margin: 0;
        padding: 0 8px;
        background-color: transparent;
        border-left: 1px solid ${colors.base02};
      }

      /* First module of the bottom bar: no separator at the screen edge. */
      #admin {
        border-left: 0;
      }

      /* Drawer children sit inside their group's frame. */
      #custom-logs,
      #custom-ip,
      #custom-containers,
      #cpu,
      #memory,
      #power-profiles-daemon,
      #temperature,
      #disk,
      #custom-tray-handle,
      #tray {
        padding: 0 6px;
      }

      #custom-host {
        padding: 0 12px;
        color: ${colors.base05};
        border-left: 0;
      }

      #workspaces {
        margin: 0;
        padding: 0;
        border-left: 1px solid ${colors.base02};
      }

      /* window#waybar outranks Stylix's .modules-left rules (3 px border, urgent fill). */
      window#waybar #workspaces button {
        margin: 0 2px;
        padding: 0 8px;
        color: ${colors.base03};
        background: transparent;
        border: none;
      }

      window#waybar #workspaces button:hover {
        color: ${colors.base05};
      }

      /* Active workspace: bold text over a 3 px rainbow line. */
      window#waybar #workspaces button.active {
        color: ${colors.base05};
        font-weight: bold;
        background-image: linear-gradient(to right,
          ${colors.base0B} 0%, ${colors.base0B} 16.67%,
          ${colors.base0A} 16.67%, ${colors.base0A} 33.33%,
          ${colors.base09} 33.33%, ${colors.base09} 50%,
          ${colors.base08} 50%, ${colors.base08} 66.67%,
          ${colors.base0E} 66.67%, ${colors.base0E} 83.33%,
          ${colors.base0D} 83.33%, ${colors.base0D} 100%);
        background-size: 100% 3px;
        background-position: bottom;
        background-repeat: no-repeat;
      }

      window#waybar #workspaces button.urgent {
        color: ${colors.base08};
      }

      #clock {
        padding: 0 16px;
        font-weight: bold;
        color: ${colors.base05};
        border-right: 1px solid ${colors.base02};
      }

      /* Bottom bar: values are dim, colour only marks a state. */
      #custom-logs,
      #custom-ip,
      #custom-containers,
      #custom-target,
      #cpu,
      #memory,
      #temperature,
      #disk,
      #power-profiles-daemon,
      #network,
      #pulseaudio,
      #bluetooth,
      #battery,
      #custom-tray-handle {
        color: ${colors.base04};
      }

      #custom-logs.ok {
        color: ${colors.base03};
      }

      #custom-logs.warn,
      #cpu.warning,
      #memory.warning,
      #battery.warning {
        color: ${colors.base0A};
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

      #custom-privacy.active {
        color: ${colors.base0E};
      }

      /* Agents, AI limit, DNS shield: teal = fine or working, yellow = needs you, red = critical, grey = stale. */
      #custom-agents.busy,
      #custom-ai.ok,
      #custom-dns.ok {
        color: ${colors.base0C};
      }

      #custom-agents.waiting,
      #custom-ai.warn {
        color: ${colors.base0A};
      }

      #custom-ai.crit,
      #custom-dns.off {
        color: ${colors.base08};
      }

      #custom-ai.stale {
        color: ${colors.base03};
      }

      /* Opened drawer modules sit on a raised surface. */
      .drawer-child {
        background-color: ${colors.base01};
      }

      #tray > .passive {
        -gtk-icon-effect: dim;
      }
    '';

    systemd.enable = true;
  };

  home.packages = [pkgs.pavucontrol];

  # Also bound to a key in hyprland/bindings.nix.
  home.file.".local/bin/waybar-stream".source = "${barStream}/bin/waybar-stream";

  # claude-hud writes its usage snapshot only into an existing directory (see barAi).
  xdg.cacheFile."claude-hud/.keep".text = "";
}
