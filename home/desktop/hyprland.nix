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

  # Home Manager's Lua renderer requires structured call arguments. Inline
  # values are limited to dispatcher callbacks that must remain Lua code.
  # Every bind carries a description flag: hyprctl binds reports Lua
  # dispatchers only as opaque "__lua N", so the description is what makes
  # binds introspectable (used by ~/.local/bin/keybinds-menu).
  lua = lib.generators.mkLuaInline;
  bind = keyCombo: dispatcher: description: {
    _args = [keyCombo (lua dispatcher) {inherit description;}];
  };
  bindWithOptions = keyCombo: dispatcher: options: description: {
    _args = [keyCombo (lua dispatcher) (options // {inherit description;})];
  };
  execBinding = keyCombo: command: description:
    bind keyCombo "hl.dsp.exec_cmd(${builtins.toJSON command})" description;
  windowRule = spec: {_args = [spec];};

  # ─── Helpers ──────────────────────────────────────────
  pactlBin = "${pkgs.pulseaudio}/bin/pactl";
  brightnessctlBin = "${pkgs.brightnessctl}/bin/brightnessctl";
  playerctlBin = "${pkgs.playerctl}/bin/playerctl";

  # Stylix's Hyprland target is disabled in home/theme.nix; this module owns
  # the window-manager palette so each Hyprland color has one definition.

  # ─── Directional focus (vim + arrows) ─────────────────
  directionalFocus = [
    (bind "${mod} + j" ''hl.dsp.focus({ direction = "left" })'' "focus window left")
    (bind "${mod} + k" ''hl.dsp.focus({ direction = "down" })'' "focus window down")
    (bind "${mod} + l" ''hl.dsp.focus({ direction = "up" })'' "focus window up")
    (bind "${mod} + semicolon" ''hl.dsp.focus({ direction = "right" })'' "focus window right")
    (bind "${mod} + Left" ''hl.dsp.focus({ direction = "left" })'' "focus window left")
    (bind "${mod} + Down" ''hl.dsp.focus({ direction = "down" })'' "focus window down")
    (bind "${mod} + Up" ''hl.dsp.focus({ direction = "up" })'' "focus window up")
    (bind "${mod} + Right" ''hl.dsp.focus({ direction = "right" })'' "focus window right")
  ];

  # ─── Directional move (Shift + vim/arrows) ────────────
  directionalMove = [
    (bind "${mod} + SHIFT + j" ''hl.dsp.window.move({ direction = "left", group_aware = true })'' "move window left")
    (bind "${mod} + SHIFT + k" ''hl.dsp.window.move({ direction = "down", group_aware = true })'' "move window down")
    (bind "${mod} + SHIFT + l" ''hl.dsp.window.move({ direction = "up", group_aware = true })'' "move window up")
    (bind "${mod} + SHIFT + semicolon" ''hl.dsp.window.move({ direction = "right", group_aware = true })'' "move window right")
    (bind "${mod} + SHIFT + Left" ''hl.dsp.window.move({ direction = "left", group_aware = true })'' "move window left")
    (bind "${mod} + SHIFT + Down" ''hl.dsp.window.move({ direction = "down", group_aware = true })'' "move window down")
    (bind "${mod} + SHIFT + Up" ''hl.dsp.window.move({ direction = "up", group_aware = true })'' "move window up")
    (bind "${mod} + SHIFT + Right" ''hl.dsp.window.move({ direction = "right", group_aware = true })'' "move window right")
  ];

  # ─── Layout management (dwindle) ──────────────────────
  # i3's parent/child focus and container-level split have no equivalent in
  # Hyprland's flat dwindle model, so those bindings are dropped rather than
  # faked; see the cheatsheet for exactly what's bound.
  layoutBindings = [
    (bind "${mod} + f" "hl.dsp.window.fullscreen()" "toggle fullscreen")
    (bind "${mod} + CTRL + f" ''hl.dsp.window.fullscreen_state({ internal = 2, client = 0, action = "toggle" })'' "fullscreen without app mode")
    (bind "${mod} + e" ''hl.dsp.layout("togglesplit")'' "toggle split orientation")
    (bind "${mod} + CTRL + e" ''hl.dsp.layout("swapsplit")'' "swap split branches")
    (bind "${mod} + s" "hl.dsp.group.toggle()" "toggle tab group")
    (bind "${mod} + Tab" "hl.dsp.group.next()" "next window in group")
    (bind "${mod} + SHIFT + Tab" "hl.dsp.group.prev()" "previous window in group")
    (bind "${mod} + CTRL + Tab" "hl.dsp.group.move_window({ forward = true })" "move window forward in group")
    (bind "${mod} + CTRL + SHIFT + Tab" "hl.dsp.group.move_window({ forward = false })" "move window backward in group")
    (bind "${mod} + CTRL + o" "hl.dsp.window.move({ out_of_group = true })" "remove window from group")
    (bind "${mod} + SHIFT + s" ''hl.dsp.group.lock_active({ action = "toggle" })'' "lock active group")
    (bind "${mod} + p" "hl.dsp.window.pseudo()" "toggle pseudotile")
    (bind "${mod} + SHIFT + SPACE" ''hl.dsp.window.float({ action = "toggle" })'' "toggle floating")
    (bind "${mod} + CTRL + SPACE" ''hl.dsp.window.pin({ action = "toggle" })'' "pin floating window")
    (bind "${mod} + a" "hl.dsp.focus({ last = true })" "focus last window")
    (bind "${mod} + g" ''hl.dsp.workspace.toggle_special("scratchpad")'' "toggle scratchpad workspace")
    (bind "${mod} + SHIFT + g" ''hl.dsp.window.move({ workspace = "special:scratchpad" })'' "move window to scratchpad")
  ];

  mouseBindings = [
    (bindWithOptions "${mod} + mouse:272" "hl.dsp.window.drag()" {mouse = true;} "drag window with mouse")
    (bindWithOptions "${mod} + mouse:273" "hl.dsp.window.resize()" {mouse = true;} "resize window with mouse")
  ];

  workspaceScroll = [
    (bind "${mod} + mouse_down" ''hl.dsp.focus({ workspace = "e+1" })'' "next workspace (scroll)")
    (bind "${mod} + mouse_up" ''hl.dsp.focus({ workspace = "e-1" })'' "previous workspace (scroll)")
  ];

  # ─── System / app launchers ────────────────────────────
  systemBindings = [
    (execBinding "${mod} + Return" "${pkgs.kitty}/bin/kitty" "open terminal (kitty)")
    (execBinding "${mod} + SHIFT + w" "${pkgs.firefox}/bin/firefox" "open Firefox")
    (execBinding "${mod} + SHIFT + e" "${pkgs.thunderbird}/bin/thunderbird" "open Thunderbird")
    (execBinding "${mod} + SHIFT + f" "${pkgs.pcmanfm}/bin/pcmanfm" "open file manager")
    (execBinding "${mod} + d" "${config.programs.rofi.package}/bin/rofi -show drun" "app launcher (rofi)")
    (execBinding "${mod} + SHIFT + v" "${pkgs.cliphist}/bin/cliphist list | ${config.programs.rofi.package}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy" "clipboard history picker")

    (bind "${mod} + SHIFT + q" "hl.dsp.window.close()" "close window")
    (execBinding "${mod} + SHIFT + c" "hyprctl reload" "reload Hyprland config")
    (bind "${mod} + r" ''hl.dsp.submap("resize")'' "enter resize mode")
    (execBinding "${mod} + SHIFT + x" "${pkgs.hyprlock}/bin/hyprlock" "lock screen")

    (execBinding "XF86PowerOff" "~/.local/bin/powermenu" "power menu")
    (execBinding "${mod} + Escape" "~/.local/bin/powermenu" "power menu")

    (execBinding "${mod} + F1" "~/.local/bin/hyprland-cheatsheet-show" "shortcut cheatsheet")
    (execBinding "${mod} + F2" "~/.local/bin/keybinds-menu" "keybinding search (rofi, incl. Neovim)")

    (execBinding "Print" "~/.local/bin/hypr-screenshot" "region screenshot")
    (execBinding "F11" "~/.local/bin/hypr-screenshot" "region screenshot")

    # Mako notification controls
    (execBinding "${mod} + grave" "${pkgs.mako}/bin/makoctl restore" "restore last notification")
    (execBinding "${mod} + SHIFT + d" "${pkgs.mako}/bin/makoctl mode -t dnd" "toggle do-not-disturb")
    (execBinding "${mod} + SHIFT + period" "${pkgs.mako}/bin/makoctl dismiss --all" "dismiss all notifications")
  ];

  # ─── Media keys ────────────────────────────────────────
  mediaKeys = [
    (execBinding "XF86AudioRaiseVolume" "${pactlBin} set-sink-volume @DEFAULT_SINK@ +5%" "volume up")
    (execBinding "XF86AudioLowerVolume" "${pactlBin} set-sink-volume @DEFAULT_SINK@ -5%" "volume down")
    (execBinding "XF86AudioMute" "${pactlBin} set-sink-mute @DEFAULT_SINK@ toggle" "mute toggle")
    (execBinding "XF86AudioMicMute" "${pactlBin} set-source-mute @DEFAULT_SOURCE@ toggle" "mic mute toggle")
    (execBinding "XF86MonBrightnessUp" "${brightnessctlBin} set +10%" "brightness up")
    (execBinding "XF86MonBrightnessDown" "${brightnessctlBin} set 10%-" "brightness down")
    (execBinding "XF86AudioPlay" "${playerctlBin} play-pause" "play/pause")
    (execBinding "XF86AudioNext" "${playerctlBin} next" "next track")
    (execBinding "XF86AudioPrev" "${playerctlBin} previous" "previous track")
  ];

  # ─── Workspaces (explicit, no helper) ─────────────────
  workspaceSwitch = builtins.genList (i: let
    n = i + 1;
  in
    bind "${mod} + ${toString (lib.mod n 10)}" "hl.dsp.focus({ workspace = ${toString n} })" "switch to workspace ${toString n}")
  10;

  workspaceMove = builtins.genList (i: let
    n = i + 1;
  in
    bind "${mod} + SHIFT + ${toString (lib.mod n 10)}" "hl.dsp.window.move({ workspace = ${toString n} })" "move window to workspace ${toString n}")
  10;

  resizeBindings = [
    (bindWithOptions "j" "hl.dsp.window.resize({ x = -10, y = 0, relative = true })" {repeating = true;} "resize window left")
    (bindWithOptions "k" "hl.dsp.window.resize({ x = 0, y = 10, relative = true })" {repeating = true;} "resize window down")
    (bindWithOptions "l" "hl.dsp.window.resize({ x = 0, y = -10, relative = true })" {repeating = true;} "resize window up")
    (bindWithOptions "semicolon" "hl.dsp.window.resize({ x = 10, y = 0, relative = true })" {repeating = true;} "resize window right")
    (bindWithOptions "Left" "hl.dsp.window.resize({ x = -10, y = 0, relative = true })" {repeating = true;} "resize window left")
    (bindWithOptions "Down" "hl.dsp.window.resize({ x = 0, y = 10, relative = true })" {repeating = true;} "resize window down")
    (bindWithOptions "Up" "hl.dsp.window.resize({ x = 0, y = -10, relative = true })" {repeating = true;} "resize window up")
    (bindWithOptions "Right" "hl.dsp.window.resize({ x = 10, y = 0, relative = true })" {repeating = true;} "resize window right")
    (bind "Return" ''hl.dsp.submap("reset")'' "exit resize mode")
    (bind "Escape" ''hl.dsp.submap("reset")'' "exit resize mode")
    (bind "${mod} + r" ''hl.dsp.submap("reset")'' "exit resize mode")
  ];

  startupCommands = [
    "${pkgs.networkmanagerapplet}/bin/nm-applet"
    "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
    "${pkgs.blueman}/bin/blueman-applet"
    "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store"
    "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store"
  ];
  startupHandler = lib.concatMapStringsSep "\n" (command: "  hl.exec_cmd(${builtins.toJSON command})") startupCommands;

  windowRules = map windowRule [
    {
      name = "pavucontrol";
      match.class = "^(pavucontrol|org.pulseaudio.pavucontrol)$";
      float = true;
      size = "900 600";
      center = true;
    }
    {
      name = "blueman-manager";
      match.class = "^(blueman-manager)$";
      float = true;
      size = "720 520";
      center = true;
    }
    {
      name = "picture-in-picture";
      match.title = "^(Picture-in-Picture)$";
      float = true;
      pin = true;
    }
    {
      name = "hyprland-shortcuts";
      match.title = "^(Hyprland Shortcuts)$";
      float = true;
      size = "800 560";
      center = true;
    }
    {
      name = "firefox-workspace";
      match.class = "^(firefox)$";
      workspace = "1";
    }
    {
      name = "pcmanfm-workspace";
      match.class = "^(pcmanfm)$";
      workspace = "3";
    }
    {
      name = "thunderbird-workspace";
      match.class = "^(thunderbird)$";
      workspace = "4";
    }
  ];
in {
  wayland.windowManager.hyprland = {
    enable = true;
    # Installed system-wide by programs.hyprland in nixos/desktop.nix.
    package = null;
    portalPackage = null;
    xwayland.enable = true;
    # Hyprland 0.57 removes the legacy .conf format. Keep Nix as the source of
    # truth while Home Manager renders the supported native Lua configuration.
    configType = "lua";

    settings = {
      monitor = {
        _args = [
          {
            output = "";
            mode = "preferred";
            position = "auto";
            scale = 1;
          }
        ];
      };

      config = {
        general = {
          gaps_in = 6;
          gaps_out = 0;
          border_size = 3;
          layout = "dwindle";
          resize_on_border = true;
          extend_border_grab_area = 10;
          hover_icon_on_border = true;

          col = {
            active_border = rgb colors.base09;
            inactive_border = rgb colors.base03;
            nogroup_border = rgb colors.base08;
            nogroup_border_active = rgb colors.base0A;
          };

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

          col = {
            border_active = rgb colors.base09;
            border_inactive = rgb colors.base03;
            border_locked_active = rgb colors.base0A;
            border_locked_inactive = rgb colors.base02;
          };

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

            col = {
              active = rgb colors.base09;
              inactive = rgb colors.base02;
              locked_active = rgb colors.base0A;
              locked_inactive = rgb colors.base03;
            };
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
            tap_to_click = true;
          };
          accel_profile = "adaptive";
        };
      };

      bind =
        directionalFocus
        ++ directionalMove
        ++ layoutBindings
        ++ systemBindings
        ++ mediaKeys
        ++ workspaceSwitch
        ++ workspaceMove
        ++ workspaceScroll
        ++ mouseBindings;

      on = {
        _args = [
          "hyprland.start"
          (lua ''
            function()
            ${startupHandler}
            end
          '')
        ];
      };

      window_rule = windowRules;
    };

    submaps = {
      resize = {
        onDispatch = "reset";
        settings.bind = resizeBindings;
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

      # ─── Shortcut cheatsheet content (plain text, piped to less) ───────
      ".local/bin/hyprland-cheatsheet".text = ''
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
            Mod+F2              keybinding search (rofi, incl. Neovim)
      '';
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
