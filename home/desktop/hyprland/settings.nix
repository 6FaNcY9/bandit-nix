{
  config,
  lib,
  ...
}: let
  r = config.bandit.theme.roles;
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
          gaps_in = 4;
          gaps_out = 0;
          border_size = 3;
          layout = "dwindle";
          resize_on_border = true;
          extend_border_grab_area = 10;
          hover_icon_on_border = true;

          col = {
            active_border = rgb r.accent;
            inactive_border = rgb r.borderInactive;
            nogroup_border = rgb r.crit;
            nogroup_border_active = rgb r.warn;
          };

          snap = {
            enabled = true;
            window_gap = 8;
            monitor_gap = 8;
            respect_gaps = true;
          };
        };

        # Lean and battery-friendly: no blur, shadows or rounding means less GPU
        # work per frame on the Framework's iGPU, and nothing to redraw at idle.
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
            border_active = rgb r.accent;
            border_inactive = rgb r.borderInactive;
            border_locked_active = rgb r.accent;
            border_locked_inactive = rgb r.line;
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
            text_color = rgb r.bg;
            text_color_inactive = rgb r.fg;
            text_color_locked_active = rgb r.bg;
            text_color_locked_inactive = rgb r.fg;

            col = {
              active = rgb r.accent;
              inactive = rgb r.surface;
              locked_active = rgb r.accent;
              locked_inactive = rgb r.line;
            };
          };
        };

        misc = {
          background_color = rgb r.bg;
          disable_hyprland_logo = true;
        };

        # Flat, snappy, retro aesthetic — no window-open/close/move animation;
        # also saves frames (and battery) on every workspace switch.
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
