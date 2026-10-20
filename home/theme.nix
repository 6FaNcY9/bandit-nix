{
  config,
  lib,
  repoConfig,
  ...
}: let
  # Stylix cascades the NixOS polarity ("dark", or "light" in the light
  # specialisation); the standalone homeConfigurations output defaults to dark.
  variant =
    if (config.stylix.polarity or "dark") == "light"
    then "light"
    else "dark";
  roles = repoConfig.palette.roles variant;
in {
  # Semantic colour roles for every hand-themed module (waybar, rofi, mako,
  # hyprland, kitty tabs, browser chrome). Modules read a role, never a base16
  # slot, so an accent means the same thing everywhere. Source: themes/palette.nix.
  options.bandit.theme.roles = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    description = "Semantic \"#rrggbb\" colours derived from themes/palette.nix for the active variant.";
  };

  config = {
    bandit.theme.roles = roles;

    # Stylix owns the cursor (nixos/theme.nix via mkStylixTheme); enable is
    # forced only to silence its HM deprecation warning.
    home.pointerCursor.enable = lib.mkForce true;

    # Stylix targets are on by default (autoEnable); list only the opt-outs:
    # these modules are themed by hand from bandit.theme.roles.
    stylix.targets = {
      hyprland.enable = false;
      rofi.enable = false;
      mako.enable = false;
      firefox = {
        firefoxGnomeTheme.enable = true;
        colorTheme.enable = true;
      };
      # Kvantum's highlight follows the focus accent instead of base0E, which
      # is the ops (magenta) role in this palette. The override re-renders
      # Stylix's own kvconfig template; nothing is vendored.
      qt.colors.override = {
        base0E = lib.removePrefix "#" roles.accent;
        "base0E-hex" = lib.removePrefix "#" roles.accent;
      };
    };

    # Flat, hard-edged chrome: square corners, 1px structure lines, the amber
    # focus accent for selection and focus, nothing animated.
    stylix.targets.gtk.extraCss = ''
      * { border-radius: 0; transition: none; box-shadow: none; }
      headerbar, .titlebar { border-bottom: 1px solid ${roles.line}; background-image: none; }
      button, entry, spinbutton, textview { border: 1px solid ${roles.line}; }
      button:hover { background-color: ${roles.raised}; }
      button:focus, entry:focus, textview:focus { outline: 1px solid ${roles.accent}; outline-offset: -1px; }
      selection, *:selected, menuitem:hover { background-color: ${roles.accent}; color: ${roles.bg}; }
      scrollbar slider { min-width: 8px; min-height: 8px; background-color: ${roles.line}; }
      scrollbar slider:hover, scrollbar slider:active { background-color: ${roles.accent}; }
      notebook > header tabs tab:checked { border-bottom: 2px solid ${roles.accent}; }
    '';

    gtk = let
      isDark = variant == "dark";
    in {
      gtk3.extraConfig = {
        gtk-application-prefer-dark-theme = isDark;
        gtk-enable-animations = false;
      };
      gtk4.extraConfig.gtk-application-prefer-dark-theme = isDark;
    };
  };
}
