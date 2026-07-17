{config, ...}: let
  colors = config.lib.stylix.colors.withHashtag;
in {
  # mako has no dunst-style per-urgency background color or GUI history
  # popup; `makoctl restore` (bound in hyprland.nix) is the closest
  # equivalent to dunst's history-pop, and a `mode=dnd` section stands in
  # for dunst's pause/resume toggle.
  services.mako = {
    enable = true;

    settings = {
      font = "JetBrainsMono Nerd Font 10";
      anchor = "top-right";
      layer = "overlay";
      width = 380;
      height = 200;
      margin = "12,12";
      padding = "12,14";
      border-size = 2;
      border-radius = 0;
      icons = true;
      max-icon-size = 32;
      markup = true;
      actions = true;
      default-timeout = 10000;

      background-color = colors.base00;
      border-color = colors.base0D;
      text-color = colors.base05;
      progress-color = "over ${colors.base02}";

      "urgency=low" = {
        border-color = colors.base01;
        text-color = colors.base03;
        default-timeout = 5000;
      };

      "urgency=critical" = {
        border-color = colors.base08;
        text-color = colors.base08;
        default-timeout = 0;
      };

      "mode=dnd" = {
        invisible = 1;
      };
    };
  };
}
