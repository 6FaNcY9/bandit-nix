{
  config,
  lib,
  pkgs,
  ...
}: let
  c = config.lib.stylix.colors;
  font = config.stylix.fonts.monospace.name;
  # The six stripes of the old Apple logo, top to bottom, in the Grey Console colours.
  stripes = [c.base0B c.base0A c.base09 c.base08 c.base0E c.base0D];
  centered = {
    halign = "center";
    valign = "center";
  };
in {
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
  programs.hyprlock = {
    enable = true;
    # Stylix sets the background and the input field colours; this adds clock, date and the stripes.
    settings = {
      label = [
        (centered
          // {
            text = "$TIME";
            font_size = 96;
            font_family = font;
            color = "rgb(${c.base05})";
            position = "0, 230";
          })
        (centered
          // {
            text = ''cmd[update:60000] date +"%d.%m.%Y"'';
            font_size = 22;
            font_family = font;
            color = "rgb(${c.base04})";
            position = "0, 140";
          })
      ];
      shape = lib.imap0 (i: color:
        centered
        // {
          size = "320, 10";
          color = "rgb(${color})";
          rounding = 0;
          border_size = 0;
          position = "0, ${toString (80 - 10 * i)}";
        })
      stripes;
      input-field =
        centered
        // {
          size = "320, 50";
          position = "0, -60";
          font_family = font;
          placeholder_text = "Finger oder Passwort";
        };
    };
  };
}
