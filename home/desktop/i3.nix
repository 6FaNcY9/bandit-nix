{
  pkgs,
  lib,
  ...
}: let
  mod = "Mod4";

  # ─── Helpers ──────────────────────────────────────────
  pactlBin = "${pkgs.pulseaudio}/bin/pactl";
  brightnessctlBin = "${pkgs.brightnessctl}/bin/brightnessctl";
  playerctlBin = "${pkgs.playerctl}/bin/playerctl";

  # ─── tomorrow-night-eighties palette ──────────────────
  # base00=#2d2d2d base01=#393939 base02=#515151 base03=#999999
  # base05=#cccccc base08=#f2777a base0A=#ffcc66 base0D=#6699cc

  # ─── Directional focus (vim + arrows) ─────────────────
  directionalFocus = {
    "${mod}+j" = "focus left";
    "${mod}+k" = "focus down";
    "${mod}+l" = "focus up";
    "${mod}+semicolon" = "focus right";
    "${mod}+Left" = "focus left";
    "${mod}+Down" = "focus down";
    "${mod}+Up" = "focus up";
    "${mod}+Right" = "focus right";
  };

  # ─── Directional move (Shift + vim/arrows) ────────────
  directionalMove = {
    "${mod}+Shift+j" = "move left";
    "${mod}+Shift+k" = "move down";
    "${mod}+Shift+l" = "move up";
    "${mod}+Shift+semicolon" = "move right";
    "${mod}+Shift+Left" = "move left";
    "${mod}+Shift+Down" = "move down";
    "${mod}+Shift+Up" = "move up";
    "${mod}+Shift+Right" = "move right";
  };

  # ─── Layout management ────────────────────────────────
  layoutBindings = {
    "${mod}+h" = "split horizontal";
    "${mod}+v" = "split vertical";
    "${mod}+e" = "layout toggle split";
    "${mod}+s" = "layout stacking";
    "${mod}+w" = "layout tabbed";
    "${mod}+f" = "fullscreen toggle";
    "${mod}+space" = "focus mode_toggle";
    "${mod}+Shift+space" = "floating toggle";
    "${mod}+p" = "focus parent";
    "${mod}+Shift+p" = "focus child";
  };

  # ─── System / app launchers ───────────────────────────
  systemBindings = {
    # Scratchpad
    "${mod}+m" = "move scratchpad";
    "${mod}+Shift+m" = "scratchpad show";

    # App launchers
    "${mod}+Return" = "exec ${pkgs.kitty}/bin/kitty";
    "${mod}+Shift+w" = "exec ${pkgs.firefox}/bin/firefox";
    "${mod}+d" = "exec ${pkgs.rofi}/bin/rofi -show drun";
    "${mod}+Shift+v" = "exec --no-startup-id ${pkgs.copyq}/bin/copyq toggle";

    # Window management
    "${mod}+Shift+q" = "kill";
    "${mod}+Shift+c" = "reload";
    "${mod}+Shift+r" = "restart";
    "${mod}+r" = ''mode "resize"'';
    "${mod}+Shift+x" = "exec ${pkgs.xfce4-screensaver}/bin/xfce4-screensaver-command --lock";
    "${mod}+q" = "move workspace to output next";

    # Power menu — hardware power button + keyboard fallback
    "XF86PowerOff" = "exec --no-startup-id ~/.local/bin/powermenu";
    "${mod}+Escape" = "exec --no-startup-id ~/.local/bin/powermenu";

    # Shortcut cheatsheet
    "${mod}+F1" = "exec --no-startup-id ~/.local/bin/i3-cheatsheet-show";

    # Screenshots — flameshot needs the env vars on i3
    "Print" = "exec --no-startup-id env XDG_CURRENT_DESKTOP=i3 XDG_SESSION_TYPE=x11 QT_QPA_PLATFORM=xcb ${pkgs.flameshot}/bin/flameshot gui";
    "F11" = "exec --no-startup-id env XDG_CURRENT_DESKTOP=i3 XDG_SESSION_TYPE=x11 QT_QPA_PLATFORM=xcb ${pkgs.flameshot}/bin/flameshot gui";

    # Dunst notification controls
    "${mod}+grave" = "exec ${pkgs.dunst}/bin/dunstctl history-pop";
    "${mod}+Shift+d" = "exec ${pkgs.dunst}/bin/dunstctl set-paused toggle";
    "${mod}+Shift+period" = "exec ${pkgs.dunst}/bin/dunstctl close-all";

    # App finder
    "${mod}+a" = "exec ${pkgs.xfce4-appfinder}/bin/xfce4-appfinder --collapsed";
  };

  # ─── Media keys ───────────────────────────────────────
  mediaKeys = {
    "XF86AudioRaiseVolume" = "exec --no-startup-id ${pactlBin} set-sink-volume @DEFAULT_SINK@ +5%";
    "XF86AudioLowerVolume" = "exec --no-startup-id ${pactlBin} set-sink-volume @DEFAULT_SINK@ -5%";
    "XF86AudioMute" = "exec --no-startup-id ${pactlBin} set-sink-mute @DEFAULT_SINK@ toggle";
    "XF86AudioMicMute" = "exec --no-startup-id ${pactlBin} set-source-mute @DEFAULT_SOURCE@ toggle";
    "XF86MonBrightnessUp" = "exec --no-startup-id ${brightnessctlBin} set +10%";
    "XF86MonBrightnessDown" = "exec --no-startup-id ${brightnessctlBin} set 10%-";
    "XF86AudioPlay" = "exec --no-startup-id ${playerctlBin} play-pause";
    "XF86AudioNext" = "exec --no-startup-id ${playerctlBin} next";
    "XF86AudioPrev" = "exec --no-startup-id ${playerctlBin} previous";
  };

  # ─── Workspaces (explicit, no helper) ─────────────────
  workspaceSwitch = {
    "${mod}+1" = "workspace number 1";
    "${mod}+2" = "workspace number 2";
    "${mod}+3" = "workspace number 3";
    "${mod}+4" = "workspace number 4";
    "${mod}+5" = "workspace number 5";
    "${mod}+6" = "workspace number 6";
    "${mod}+7" = "workspace number 7";
    "${mod}+8" = "workspace number 8";
    "${mod}+9" = "workspace number 9";
    "${mod}+0" = "workspace number 10";
  };

  workspaceMove = {
    "${mod}+Shift+1" = "move container to workspace number 1";
    "${mod}+Shift+2" = "move container to workspace number 2";
    "${mod}+Shift+3" = "move container to workspace number 3";
    "${mod}+Shift+4" = "move container to workspace number 4";
    "${mod}+Shift+5" = "move container to workspace number 5";
    "${mod}+Shift+6" = "move container to workspace number 6";
    "${mod}+Shift+7" = "move container to workspace number 7";
    "${mod}+Shift+8" = "move container to workspace number 8";
    "${mod}+Shift+9" = "move container to workspace number 9";
    "${mod}+Shift+0" = "move container to workspace number 10";
  };
in {
  xsession.windowManager.i3 = {
    enable = true;
    config = {
      modifier = mod;

      fonts = {
        names = lib.mkForce ["JetBrainsMono Nerd Font Mono"];
        size = lib.mkForce 10.0;
      };

      # ─── Keybindings ────────────────────────────────────
      keybindings = lib.mkOptionDefault (
        directionalFocus
        // directionalMove
        // layoutBindings
        // systemBindings
        // mediaKeys
        // workspaceSwitch
        // workspaceMove
      );

      # ─── Resize mode ────────────────────────────────────
      modes.resize = {
        "j" = "resize shrink width 10 px or 10 ppt";
        "k" = "resize grow height 10 px or 10 ppt";
        "l" = "resize shrink height 10 px or 10 ppt";
        "semicolon" = "resize grow width 10 px or 10 ppt";
        "Left" = "resize shrink width 10 px or 10 ppt";
        "Down" = "resize grow height 10 px or 10 ppt";
        "Up" = "resize shrink height 10 px or 10 ppt";
        "Right" = "resize grow width 10 px or 10 ppt";
        "Return" = "mode default";
        "Escape" = "mode default";
        "${mod}+r" = "mode default";
      };

      # ─── Floating windows ───────────────────────────────
      floating = {
        modifier = mod;
        titlebar = true;
        border = 2;
        criteria = [
          {class = "Pavucontrol";}
          {class = "Blueman-manager";}
          {class = "flameshot";}
          {class = "copyq";}
          {title = "Picture-in-Picture";}
          {title = "i3 Shortcuts";}
        ];
      };

      # ─── Window appearance ──────────────────────────────
      gaps = {
        inner = 6;
        outer = 0;
        smartGaps = true;
        smartBorders = "on";
      };

      window = {
        border = 3;
        titlebar = false;
      };

      # ─── Window colors (tomorrow-night-eighties) ────────
      colors = {
        focused = {
          border = lib.mkForce "#ffcc66";
          background = lib.mkForce "#2d2d2d";
          text = lib.mkForce "#cccccc";
          indicator = lib.mkForce "#6699cc";
          childBorder = lib.mkForce "#ffcc66";
        };
        focusedInactive = {
          border = lib.mkForce "#393939";
          background = lib.mkForce "#2d2d2d";
          text = lib.mkForce "#999999";
          indicator = lib.mkForce "#393939";
          childBorder = lib.mkForce "#393939";
        };
        unfocused = {
          border = lib.mkForce "#393939";
          background = lib.mkForce "#2d2d2d";
          text = lib.mkForce "#999999";
          indicator = lib.mkForce "#393939";
          childBorder = lib.mkForce "#393939";
        };
        urgent = {
          border = lib.mkForce "#f2777a";
          background = lib.mkForce "#f2777a";
          text = lib.mkForce "#cccccc";
          indicator = lib.mkForce "#f2777a";
          childBorder = lib.mkForce "#f2777a";
        };
      };

      # ─── Startup applications ───────────────────────────
      startup = [
        {
          command = "${pkgs.autotiling}/bin/autotiling";
          notification = false;
        }
        # Lock screen on suspend (xfce4-power-manager handles idle lock)
        {
          command = "${pkgs.xss-lock}/bin/xss-lock -- ${pkgs.xfce4-screensaver}/bin/xfce4-screensaver-command --lock";
          notification = false;
        }
        {
          command = "${pkgs.networkmanagerapplet}/bin/nm-applet";
          notification = false;
        }
        {
          command = "${pkgs.blueman}/bin/blueman-applet";
          notification = false;
        }
        {
          command = "${pkgs.copyq}/bin/copyq";
          notification = false;
        }
        # XFCE panel — provides system tray since you're running XFCE+i3
        {
          command = "${pkgs.xfce4-panel}/bin/xfce4-panel --disable-wm-check";
          notification = false;
        }
      ];

      # No default i3bar since XFCE panel handles that
      bars = [];
    };
  };

  home.file = {
    # ─── Shortcut cheatsheet launcher (Mod+F1) ───────────
    ".local/bin/i3-cheatsheet-show" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec kitty --title 'i3 Shortcuts' \
          --override remember_window_size=no \
          --override initial_window_width=800 \
          --override initial_window_height=560 \
          bash -c 'cat ~/.local/bin/i3-cheatsheet | less -R'
      '';
    };

    # ─── Shortcut cheatsheet content ─────────────────────
    ".local/bin/i3-cheatsheet" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        cat <<'EOF'
        ╔══════════════════════════════════════════════════════════╗
        ║           i3 Shortcuts  (Mod = Super / Win key)          ║
        ╚══════════════════════════════════════════════════════════╝

        LAUNCH
          Mod+Return          kitty (terminal)
          Mod+Shift+W         firefox
          Mod+D               rofi app launcher
          Mod+Shift+V         copyq clipboard manager
          Mod+A               XFCE app finder

        WINDOWS
          Mod+Shift+Q         kill focused window
          Mod+F               fullscreen toggle
          Mod+Shift+Space     toggle float/tile
          Mod+Space           focus float ↔ tile
          Mod+Shift+X         lock screen

        FOCUS  (also works with arrow keys)
          Mod+J               focus left
          Mod+K               focus down
          Mod+L               focus up
          Mod+;               focus right

        MOVE  (also works with arrow keys)
          Mod+Shift+J         move left
          Mod+Shift+K         move down
          Mod+Shift+L         move up
          Mod+Shift+;         move right

        LAYOUT
          Mod+H               split horizontal
          Mod+V               split vertical
          Mod+E               toggle split
          Mod+S               stacking layout
          Mod+W               tabbed layout
          Mod+P / Shift+P     focus parent / child

        RESIZE MODE  (Mod+R, then…)
          J/K/L/; or Arrows   resize window
          Return / Escape     exit resize mode

        WORKSPACES
          Mod+1…0             switch to workspace 1–10
          Mod+Shift+1…0       move window to workspace

        SCRATCHPAD
          Mod+M               send to scratchpad
          Mod+Shift+M         show scratchpad

        NOTIFICATIONS (dunst)
          Mod+`               show notification history
          Mod+Shift+D         pause / resume notifications
          Mod+Shift+.         close all notifications

        SCREENSHOTS
          Print / F11         flameshot GUI screenshot

        MEDIA
          XF86AudioRaise/Lower  volume ±5%
          XF86AudioMute         mute toggle
          XF86MonBrightness+/-  screen brightness
          XF86AudioPlay/Next/Prev  media control

        i3 CONFIG
          Mod+Shift+C         reload config
          Mod+Shift+R         restart i3
          Mod+F1              this help screen

        EOF
      '';
    };
  };

  # ─── Required packages ────────────────────────────────
  home.packages = with pkgs; [
    flameshot
    xss-lock
    copyq
    playerctl
    brightnessctl
    networkmanagerapplet
    autotiling
    less
  ];
}
