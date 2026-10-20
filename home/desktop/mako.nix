{config, ...}: let
  r = config.bandit.theme.roles;
in {
  # mako has no dunst-style per-urgency background color or GUI history
  # popup; `makoctl restore` (bound in home/desktop/hyprland/bindings.nix) is the closest
  # equivalent to dunst's history-pop, and a `mode=dnd` section stands in
  # for dunst's pause/resume toggle.
  services.mako = {
    enable = true;

    settings = {
      font = "${config.stylix.fonts.sansSerif.name} 10";
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

      background-color = r.bg;
      border-color = r.line;
      text-color = r.fg;
      progress-color = "over ${r.raised}";

      "urgency=low" = {
        border-color = r.line;
        text-color = r.muted;
        default-timeout = 5000;
      };

      "urgency=critical" = {
        border-color = r.crit;
        text-color = r.crit;
        default-timeout = 0;
      };

      "mode=dnd" = {
        invisible = 1;
      };
    };
  };
}
