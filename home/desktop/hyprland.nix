{
  config,
  pkgs,
  lib,
  repoConfig,
  ...
}: let
  mod = "SUPER";
  colors = config.lib.stylix.colors.withHashtag;
  rgb = color: "rgb(${lib.removePrefix "#" color})";

  # ─── Helpers ──────────────────────────────────────────
  pactlBin = "${pkgs.pulseaudio}/bin/pactl";
  brightnessctlBin = "${pkgs.brightnessctl}/bin/brightnessctl";
  playerctlBin = "${pkgs.playerctl}/bin/playerctl";

  # Stylix's Hyprland target is disabled in home/theme.nix; this module owns
  # the window-manager palette so each Hyprland color has one definition.

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
    "${mod} SHIFT, j, movewindoworgroup, l"
    "${mod} SHIFT, k, movewindoworgroup, d"
    "${mod} SHIFT, l, movewindoworgroup, u"
    "${mod} SHIFT, semicolon, movewindoworgroup, r"
    "${mod} SHIFT, Left, movewindoworgroup, l"
    "${mod} SHIFT, Down, movewindoworgroup, d"
    "${mod} SHIFT, Up, movewindoworgroup, u"
    "${mod} SHIFT, Right, movewindoworgroup, r"
  ];

  # ─── Layout management (dwindle) ──────────────────────
  # i3's parent/child focus and container-level split have no equivalent in
  # Hyprland's flat dwindle model, so those bindings are dropped rather than
  # faked; see the cheatsheet for exactly what's bound.
  layoutBindings = [
    "${mod}, f, fullscreen, 0"
    "${mod} CTRL, f, fullscreenstate, 2 0"
    "${mod}, e, layoutmsg, togglesplit"
    "${mod} CTRL, e, layoutmsg, swapsplit"
    "${mod}, s, togglegroup"
    "${mod}, Tab, changegroupactive, f"
    "${mod} SHIFT, Tab, changegroupactive, b"
    "${mod} CTRL, Tab, movegroupwindow, f"
    "${mod} CTRL SHIFT, Tab, movegroupwindow, b"
    "${mod} CTRL, o, moveoutofgroup"
    "${mod} SHIFT, s, lockactivegroup, toggle"
    "${mod}, p, pseudo"
    "${mod} SHIFT, SPACE, togglefloating"
    "${mod} CTRL, SPACE, pin"
    "${mod}, a, focuscurrentorlast"
    "${mod}, g, togglespecialworkspace, scratchpad"
    "${mod} SHIFT, g, movetoworkspace, special:scratchpad"
  ];

  mouseBindings = [
    "${mod}, mouse:272, movewindow"
    "${mod}, mouse:273, resizewindow"
  ];

  workspaceScroll = [
    "${mod}, mouse_down, workspace, e+1"
    "${mod}, mouse_up, workspace, e-1"
  ];

  # ─── System / app launchers ────────────────────────────
  systemBindings = [
    "${mod}, Return, exec, ${pkgs.kitty}/bin/kitty"
    "${mod} SHIFT, w, exec, ${pkgs.firefox}/bin/firefox"
    "${mod} SHIFT, e, exec, ${pkgs.thunderbird}/bin/thunderbird"
    "${mod} SHIFT, f, exec, ${pkgs.pcmanfm}/bin/pcmanfm"
    "${mod}, d, exec, ${config.programs.rofi.package}/bin/rofi -show drun"
    "${mod} SHIFT, v, exec, ${pkgs.cliphist}/bin/cliphist list | ${config.programs.rofi.package}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy"

    "${mod} SHIFT, q, killactive"
    "${mod} SHIFT, c, exec, hyprctl reload"
    "${mod}, r, submap, resize"
    "${mod} SHIFT, x, exec, ${pkgs.hyprlock}/bin/hyprlock"

    ", XF86PowerOff, exec, ~/.local/bin/powermenu"
    "${mod}, Escape, exec, ~/.local/bin/powermenu"

    "${mod}, F1, exec, ~/.local/bin/hyprland-cheatsheet-show"

    ", Print, exec, ~/.local/bin/hypr-screenshot"
    ", F11, exec, ~/.local/bin/hypr-screenshot"

    # Mako notification controls
    "${mod}, grave, exec, ${pkgs.mako}/bin/makoctl restore"
    "${mod} SHIFT, d, exec, ${pkgs.mako}/bin/makoctl mode -t dnd"
    "${mod} SHIFT, period, exec, ${pkgs.mako}/bin/makoctl dismiss --all"
  ];

  # ─── Media keys ────────────────────────────────────────
  mediaKeys = [
    ", XF86AudioRaiseVolume, exec, ${pactlBin} set-sink-volume @DEFAULT_SINK@ +5%"
    ", XF86AudioLowerVolume, exec, ${pactlBin} set-sink-volume @DEFAULT_SINK@ -5%"
    ", XF86AudioMute, exec, ${pactlBin} set-sink-mute @DEFAULT_SINK@ toggle"
    ", XF86AudioMicMute, exec, ${pactlBin} set-source-mute @DEFAULT_SOURCE@ toggle"
    ", XF86MonBrightnessUp, exec, ${brightnessctlBin} set +10%"
    ", XF86MonBrightnessDown, exec, ${brightnessctlBin} set 10%-"
    ", XF86AudioPlay, exec, ${playerctlBin} play-pause"
    ", XF86AudioNext, exec, ${playerctlBin} next"
    ", XF86AudioPrev, exec, ${playerctlBin} previous"
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
        resize_on_border = true;
        extend_border_grab_area = 10;
        hover_icon_on_border = true;
        "col.active_border" = rgb colors.base09;
        "col.inactive_border" = rgb colors.base03;
        "col.nogroup_border" = rgb colors.base08;
        "col.nogroup_border_active" = rgb colors.base0A;

        snap = {
          enabled = true;
          window_gap = 8;
          monitor_gap = 8;
          respect_gaps = true;
        };
      };

      decoration = {
        rounding = 0;
        blur.enabled = false;
        shadow.enabled = false;
      };

      dwindle = {
        preserve_split = true;
      };

      group = {
        auto_group = true;
        insert_after_current = true;
        focus_removed_window = true;
        drag_into_group = 2;
        merge_groups_on_drag = true;
        merge_groups_on_groupbar = true;
        "col.border_active" = rgb colors.base09;
        "col.border_inactive" = rgb colors.base03;
        "col.border_locked_active" = rgb colors.base0A;
        "col.border_locked_inactive" = rgb colors.base02;

        groupbar = {
          enabled = true;
          font_family = config.stylix.fonts.monospace.name;
          # Was 10px/20px — unreadable on the Framework 13 panel and
          # visually disconnected from Waybar. 13px/26px lands between
          # Waybar's 16px text and the window content scale.
          font_size = 13;
          gradients = false;
          height = 26;
          indicator_height = 3;
          stacked = false;
          render_titles = true;
          scrolling = true;
          rounding = 0;
          gradient_rounding = 0;
          gaps_in = 1;
          gaps_out = 0;
          text_color = rgb colors.base00;
          text_color_inactive = rgb colors.base05;
          text_color_locked_active = rgb colors.base00;
          text_color_locked_inactive = rgb colors.base04;
          "col.active" = rgb colors.base09;
          "col.inactive" = rgb colors.base02;
          "col.locked_active" = rgb colors.base0A;
          "col.locked_inactive" = rgb colors.base03;
        };
      };

      misc = {
        background_color = rgb colors.base00;
        disable_hyprland_logo = true;
      };

      # Flat, snappy, retro aesthetic — no window-open/close/move animation.
      animations.enabled = false;

      input = {
        # Hyprland does not inherit the virtual-console keymap. Keep the
        # graphical session on the Austrian layout used by the previous i3
        # configuration instead of falling back to XKB's US default.
        kb_layout = "at";

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
        ++ workspaceMove
        ++ workspaceScroll;

      bindm = mouseBindings;

      exec-once = [
        "${pkgs.networkmanagerapplet}/bin/nm-applet"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "${pkgs.blueman}/bin/blueman-applet"
        "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store"
        "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store"
      ];

      # Hyprland 0.56 syntax: windowrulev2 is deprecated; effects + match: props
      windowrule = [
        "float on, match:class ^(pavucontrol|org.pulseaudio.pavucontrol)$"
        "size 900 600, match:class ^(pavucontrol|org.pulseaudio.pavucontrol)$"
        "center on, match:class ^(pavucontrol|org.pulseaudio.pavucontrol)$"

        "float on, match:class ^(blueman-manager)$"
        "size 720 520, match:class ^(blueman-manager)$"
        "center on, match:class ^(blueman-manager)$"

        "float on, match:title ^(Picture-in-Picture)$"
        "pin on, match:title ^(Picture-in-Picture)$"

        "float on, match:title ^(Hyprland Shortcuts)$"
        "size 800 560, match:title ^(Hyprland Shortcuts)$"
        "center on, match:title ^(Hyprland Shortcuts)$"

        "workspace 1, match:class ^(firefox)$"
        "workspace 3, match:class ^(pcmanfm)$"
        "workspace 4, match:class ^(thunderbird)$"
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
              Mod+Shift+V         cliphist clipboard picker
              Mod+Shift+F         PCManFM file manager

            WINDOWS
              Mod+Shift+Q         kill focused window
              Mod+F               fullscreen toggle
          Mod+Ctrl+F          fullscreen without app mode
              Mod+Shift+Space     toggle float/tile
              Mod+Ctrl+Space      pin floating window
              Mod+A               focus current/last window
              Mod+Shift+X         lock screen

            FOCUS  (also works with arrow keys)
              Mod+J               focus left
              Mod+K               focus down
              Mod+L               focus up
              Mod+;               focus right

            MOVE  (also works with arrow keys)
              Mod+Shift+J         move/group left
              Mod+Shift+K         move/group down
              Mod+Shift+L         move/group up
              Mod+Shift+;         move/group right

            LAYOUT (dwindle)
              Mod+E               toggle split orientation
              Mod+Ctrl+E          swap split branches
              Mod+S               toggle tab group
              Mod+Shift+S         lock active group
              Mod+P               toggle pseudotile

            GROUPS / STACKS
              Mod+Tab             next tab in group
              Mod+Shift+Tab       previous tab in group
              Mod+Ctrl+Tab        move tab forward in group
              Mod+Ctrl+Shift+Tab  move tab backward in group
              Mod+Ctrl+O          remove window from group

            RESIZE MODE  (Mod+R, then…)
              J/K/L/; or Arrows   resize window
              Return / Escape     exit resize mode

            WORKSPACES
              Mod+1…0             switch to workspace 1–10
              Mod+Shift+1…0       move window to workspace
              Mod+mouse wheel     cycle workspaces
              Mod+G               show/hide scratchpad
              Mod+Shift+G         move window to scratchpad

            MOUSE
              Mod+left drag       move window
              Mod+right drag      resize window

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
