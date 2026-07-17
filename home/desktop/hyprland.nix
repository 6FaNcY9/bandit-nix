{
  pkgs,
  lib,
  repoConfig,
  ...
}: let
  mod = "SUPER";

  # ─── Helpers ──────────────────────────────────────────
  pactlBin = "${pkgs.pipewire}/bin/pactl";
  brightnessctlBin = "${pkgs.brightnessctl}/bin/brightnessctl";
  playerctlBin = "${pkgs.playerctl}/bin/playerctl";

  # Border/accent colors are themed by Stylix's hyprland target
  # (stylix.targets.hyprland, enabled in home/theme.nix); this file only
  # owns structure/behavior, not palette values.

  # ─── Directional focus (vim + arrows) ─────────────────
  directionalFocus = [
    "${mod}, j, movefocus, l"
    "${mod}, k, movefocus, d"
    "${mod}, l, movefocus, u"
    "${mod}, semicolon, movefocus, r"
    "${mod}, Left, movefocus, l"
    "${mod}, Down, movefocus, d"
    "${mod}, Up, movefocus, u"
    "${mod}, Right, movefocus, r"
  ];

  # ─── Directional move (Shift + vim/arrows) ────────────
  directionalMove = [
    "${mod} SHIFT, j, movewindow, l"
    "${mod} SHIFT, k, movewindow, d"
    "${mod} SHIFT, l, movewindow, u"
    "${mod} SHIFT, semicolon, movewindow, r"
    "${mod} SHIFT, Left, movewindow, l"
    "${mod} SHIFT, Down, movewindow, d"
    "${mod} SHIFT, Up, movewindow, u"
    "${mod} SHIFT, Right, movewindow, r"
  ];

  # ─── Layout management (dwindle) ──────────────────────
  # i3's parent/child focus and container-level split have no equivalent in
  # Hyprland's flat dwindle model, so those bindings are dropped rather than
  # faked; see the cheatsheet for exactly what's bound.
  layoutBindings = [
    "${mod}, f, fullscreen, 0"
    "${mod}, e, togglesplit"
    "${mod}, s, togglegroup"
    "${mod} SHIFT, s, lockactivegroup, toggle"
    "${mod}, p, pseudo"
    "${mod} SHIFT, SPACE, togglefloating"
  ];

  # ─── System / app launchers ────────────────────────────
  systemBindings = [
    "${mod}, Return, exec, ${pkgs.kitty}/bin/kitty"
    "${mod} SHIFT, w, exec, ${pkgs.firefox}/bin/firefox"
    "${mod} SHIFT, e, exec, ${pkgs.thunderbird}/bin/thunderbird"
    "${mod} SHIFT, f, exec, ${pkgs.pcmanfm}/bin/pcmanfm"
    "${mod}, d, exec, ${pkgs.rofi}/bin/rofi -show drun"
    "${mod} SHIFT, v, exec, ${pkgs.copyq}/bin/copyq toggle"

    "${mod} SHIFT, q, killactive"
    "${mod} SHIFT, c, exec, hyprctl reload"
    "${mod}, r, submap, resize"
    "${mod} SHIFT, x, exec, ${pkgs.hyprlock}/bin/hyprlock"

    "XF86PowerOff, exec, ~/.local/bin/powermenu"
    "${mod}, Escape, exec, ~/.local/bin/powermenu"

    "${mod}, F1, exec, ~/.local/bin/hyprland-cheatsheet-show"

    "Print, exec, ~/.local/bin/hypr-screenshot"
    "F11, exec, ~/.local/bin/hypr-screenshot"

    # Mako notification controls
    "${mod}, grave, exec, ${pkgs.mako}/bin/makoctl restore"
    "${mod} SHIFT, d, exec, ${pkgs.mako}/bin/makoctl mode -t dnd"
    "${mod} SHIFT, period, exec, ${pkgs.mako}/bin/makoctl dismiss --all"
  ];

  # ─── Media keys ────────────────────────────────────────
  mediaKeys = [
    "XF86AudioRaiseVolume, exec, ${pactlBin} set-sink-volume @DEFAULT_SINK@ +5%"
    "XF86AudioLowerVolume, exec, ${pactlBin} set-sink-volume @DEFAULT_SINK@ -5%"
    "XF86AudioMute, exec, ${pactlBin} set-sink-mute @DEFAULT_SINK@ toggle"
    "XF86AudioMicMute, exec, ${pactlBin} set-source-mute @DEFAULT_SOURCE@ toggle"
    "XF86MonBrightnessUp, exec, ${brightnessctlBin} set +10%"
    "XF86MonBrightnessDown, exec, ${brightnessctlBin} set 10%-"
    "XF86AudioPlay, exec, ${playerctlBin} play-pause"
    "XF86AudioNext, exec, ${playerctlBin} next"
    "XF86AudioPrev, exec, ${playerctlBin} previous"
  ];

  # ─── Workspaces (explicit, no helper) ─────────────────
  workspaceSwitch = builtins.genList (i: let
    n = i + 1;
  in "${mod}, ${toString (lib.mod n 10)}, workspace, ${toString n}")
  10;

  workspaceMove = builtins.genList (i: let
    n = i + 1;
  in "${mod} SHIFT, ${toString (lib.mod n 10)}, movetoworkspace, ${toString n}")
  10;
in {
  wayland.windowManager.hyprland = {
    enable = true;
    # Installed system-wide by programs.hyprland in nixos/desktop.nix.
    package = null;
    portalPackage = null;
    xwayland.enable = true;
    configType = "hyprlang";

    settings = {
      "$mod" = mod;

      monitor = ",preferred,auto,1";

      general = {
        gaps_in = 6;
        gaps_out = 0;
        border_size = 3;
        layout = "dwindle";
      };

      decoration = {
        rounding = 0;
        blur.enabled = false;
        drop_shadow = false;
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      # Flat, snappy, retro aesthetic — no window-open/close/move animation.
      animations.enabled = false;

      input = {
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
          tap-to-click = true;
        };
        accel_profile = "adaptive";
      };

      bind =
        directionalFocus
        ++ directionalMove
        ++ layoutBindings
        ++ systemBindings
        ++ mediaKeys
        ++ workspaceSwitch
        ++ workspaceMove;

      exec-once = [
        "${pkgs.networkmanagerapplet}/bin/nm-applet"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "${pkgs.blueman}/bin/blueman-applet"
        "${pkgs.copyq}/bin/copyq"
      ];

      windowrulev2 = [
        "float, class:^(Pavucontrol)$"
        "float, class:^(Blueman-manager)$"
        "float, class:^(copyq)$"
        "float, title:^(Picture-in-Picture)$"
        "float, title:^(Hyprland Shortcuts)$"
        "workspace 1, class:^(firefox)$"
        "workspace 4, class:^(thunderbird)$"
        "workspace 3, class:^(Pcmanfm)$"
      ];
    };

    submaps = {
      resize = {
        onDispatch = "reset";
        settings = {
          binde = [
            ", j, resizeactive, -10 0"
            ", k, resizeactive, 0 10"
            ", l, resizeactive, 0 -10"
            ", semicolon, resizeactive, 10 0"
            ", Left, resizeactive, -10 0"
            ", Down, resizeactive, 0 10"
            ", Up, resizeactive, 0 -10"
            ", Right, resizeactive, 10 0"
          ];
          bind = [
            ", Return, submap, reset"
            ", Escape, submap, reset"
            "${mod}, r, submap, reset"
          ];
        };
      };
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "${pkgs.hyprlock}/bin/hyprlock";
        before_sleep_cmd = "${pkgs.hyprlock}/bin/hyprlock";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 600;
          on-timeout = "${pkgs.hyprlock}/bin/hyprlock";
        }
        {
          timeout = 900;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  services.hyprpaper.enable = true;
  programs.hyprlock.enable = true;

  home = {
    file = {
      "Pictures/Screenshots/.keep".text = "";

      # ─── Region screenshot: capture, save, copy, notify ───
      ".local/bin/hypr-screenshot" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          dir="${repoConfig.workstation.homeDirectory}/Pictures/Screenshots"
          mkdir -p "$dir"
          file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
          ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "$file"
          ${pkgs.wl-clipboard}/bin/wl-copy < "$file"
          ${pkgs.libnotify}/bin/notify-send -a hypr-screenshot "Screenshot saved" "$file"
        '';
      };

      # ─── Shortcut cheatsheet launcher (Mod+F1) ────────────
      ".local/bin/hyprland-cheatsheet-show" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          exec kitty --title 'Hyprland Shortcuts' \
            --override remember_window_size=no \
            --override initial_window_width=800 \
            --override initial_window_height=560 \
            bash -c 'cat ~/.local/bin/hyprland-cheatsheet | less -R'
        '';
      };

      # ─── Shortcut cheatsheet content ───────────────────────
      ".local/bin/hyprland-cheatsheet" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          cat <<'EOF'
          ╔══════════════════════════════════════════════════════════╗
          ║        Hyprland Shortcuts  (Mod = Super / Win key)       ║
          ╚══════════════════════════════════════════════════════════╝

          LAUNCH
            Mod+Return          kitty (terminal)
            Mod+Shift+W         firefox
            Mod+D               rofi app launcher
            Mod+Shift+V         copyq clipboard manager
            Mod+Shift+F         PCManFM file manager

          WINDOWS
            Mod+Shift+Q         kill focused window
            Mod+F               fullscreen toggle
            Mod+Shift+Space     toggle float/tile
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

          LAYOUT (dwindle)
            Mod+E               toggle split orientation
            Mod+S               toggle tab group
            Mod+Shift+S         lock active group
            Mod+P               toggle pseudotile

          RESIZE MODE  (Mod+R, then…)
            J/K/L/; or Arrows   resize window
            Return / Escape     exit resize mode

          WORKSPACES
            Mod+1…0             switch to workspace 1–10
            Mod+Shift+1…0       move window to workspace

          NOTIFICATIONS (mako)
            Mod+`               restore last dismissed notification
            Mod+Shift+D         toggle do-not-disturb
            Mod+Shift+.         dismiss all notifications

          SCREENSHOTS
            Print / F11         region screenshot (grim + slurp)

          MEDIA
            XF86AudioRaise/Lower  volume ±5%
            XF86AudioMute         mute toggle
            XF86MonBrightness+/-  screen brightness
            XF86AudioPlay/Next/Prev  media control

          HYPRLAND
            Mod+Shift+C         reload config
            Mod+F1              this help screen

          EOF
        '';
      };
    };

    packages = with pkgs; [
      grim
      slurp
      wl-clipboard
      cliphist
      libnotify
      playerctl
      brightnessctl
      networkmanagerapplet
      less
    ];
  };
}
