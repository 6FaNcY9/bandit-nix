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
    "${mod}+a" = "focus parent";
    "${mod}+Shift+a" = "focus child";
  };

  # ─── System / app launchers ───────────────────────────
  systemBindings = {
    # Scratchpad
    "${mod}+m" = "move scratchpad";
    "${mod}+Shift+m" = "scratchpad show";

    # App launchers
    "${mod}+Return" = "exec ${pkgs.xfce4-terminal}/bin/xfce4-terminal";
    "${mod}+Shift+w" = "exec ${pkgs.firefox}/bin/firefox";
    "${mod}+d" = "exec ${pkgs.rofi}/bin/rofi -show drun";
    "${mod}+Shift+v" = "exec --no-startup-id ${pkgs.copyq}/bin/copyq toggle";

    # Window management
    "${mod}+Shift+q" = "kill";
    "${mod}+Shift+c" = "reload";
    "${mod}+Shift+r" = "restart";
    "${mod}+r" = ''mode "resize"'';
    "${mod}+Shift+x" = "exec ${pkgs.i3lock}/bin/i3lock -c 262626";

    # Screenshots — flameshot needs the env vars on i3
    "Print" = "exec --no-startup-id env XDG_CURRENT_DESKTOP=i3 XDG_SESSION_TYPE=x11 QT_QPA_PLATFORM=xcb ${pkgs.flameshot}/bin/flameshot gui";
    "F11" = "exec --no-startup-id env XDG_CURRENT_DESKTOP=i3 XDG_SESSION_TYPE=x11 QT_QPA_PLATFORM=xcb ${pkgs.flameshot}/bin/flameshot gui";

    # Dunst notification controls
    "${mod}+grave" = "exec ${pkgs.dunst}/bin/dunstctl history-pop";
    "${mod}+Shift+d" = "exec ${pkgs.dunst}/bin/dunstctl set-paused toggle";
    "${mod}+Shift+period" = "exec ${pkgs.dunst}/bin/dunstctl close-all";
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
        criteria = [
          {class = "Pavucontrol";}
          {class = "Blueman-manager";}
          {class = "flameshot";}
          {title = "Picture-in-Picture";}
        ];
      };

      # ─── Window appearance ──────────────────────────────
      gaps = {
        inner = 8;
        outer = 4;
        smartGaps = true;
        smartBorders = "on";
      };

      window = {
        border = 2;
        titlebar = false;
      };

      # ─── Startup applications ───────────────────────────
      startup = [
        # Lock screen automatically before suspend.
        {
          command = "${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${pkgs.i3lock}/bin/i3lock -c 262626 -n";
          notification = false;
        }
        {
          command = "${pkgs.dunst}/bin/dunst";
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

  # ─── Required packages ────────────────────────────────
  home.packages = with pkgs; [
    rofi
    flameshot
    xss-lock
    dunst
    copyq
    playerctl
    brightnessctl
    pulseaudio # for pactl
    networkmanagerapplet
  ];
}
