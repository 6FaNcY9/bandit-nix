{
  config,
  lib,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  rgb = color: "rgb(${lib.removePrefix "#" color})";
in {
  # Stylix's Hyprland target is disabled in home/theme.nix; this module owns
  # the window-manager palette so each Hyprland color has one definition.
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
          # 6 px to the screen and bar edges, 2 x 3 between tiles.
          gaps_in = 3;
          gaps_out = 6;
          border_size = 3;
          layout = "dwindle";
          resize_on_border = true;
          extend_border_grab_area = 10;
          hover_icon_on_border = true;

          col = {
            # One focus colour (teal), readable from a distance; the rainbow
            # stays a signature in Waybar, hyprlock and the wallpaper.
            active_border = rgb colors.base0C;
            inactive_border = rgb colors.base02;
            nogroup_border = rgb colors.base02;
            nogroup_border_active = rgb colors.base0E;
          };

          snap = {
            enabled = true;
            window_gap = 6;
            monitor_gap = 6;
            respect_gaps = true;
          };
        };

        decoration = {
          rounding = 2;
          dim_inactive = true;
          dim_strength = 0.15;
          blur.enabled = false;
          shadow.enabled = false;
        };

        dwindle = {
          preserve_split = true;
        };

        master = {
          mfact = 0.66;
          new_status = "slave";
          orientation = "left";
        };

        group = {
          auto_group = true;
          insert_after_current = true;
          focus_removed_window = true;
          drag_into_group = 2;
          merge_groups_on_drag = true;
          merge_groups_on_groupbar = true;

          col = {
            border_active = rgb colors.base0C;
            border_inactive = rgb colors.base02;
            border_locked_active = rgb colors.base0E;
            border_locked_inactive = rgb colors.base02;
          };

          groupbar = {
            enabled = true;
            font_family = config.stylix.fonts.monospace.name;
            # Same text size as Waybar (Stylix desktop size, pt -> px).
            font_size = builtins.floor (config.stylix.fonts.sizes.desktop * 4 / 3);
            # Filled tabs: the active one is teal with dark text, the rest grey.
            gradients = true;
            height = builtins.floor (config.stylix.fonts.sizes.desktop * 4 / 3 * 1.6);
            indicator_height = 0;
            stacked = false;
            render_titles = true;
            scrolling = true;
            rounding = 2;
            gradient_rounding = 2;
            gaps_in = 2;
            gaps_out = 2;
            text_color = rgb colors.base00;
            text_color_inactive = rgb colors.base04;
            text_color_locked_active = rgb colors.base00;
            text_color_locked_inactive = rgb colors.base04;

            col = {
              active = rgb colors.base0C;
              inactive = rgb colors.base01;
              locked_active = rgb colors.base0E;
              locked_inactive = rgb colors.base02;
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
    };
  };
}
