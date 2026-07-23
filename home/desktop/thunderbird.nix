{
  config,
  lib,
  pkgs,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  themedChrome =
    lib.replaceStrings
    ["#282828" "#1d2021" "#3c3836" "#504945" "#928374" "#d5c4a1" "#d79921" "#458588" "#cc241d" "#98971a"]
    [colors.base00 colors.base01 colors.base01 colors.base02 colors.base03 colors.base05 colors.base0A colors.base0C colors.base08 colors.base0B]
    (builtins.readFile ./thunderbird-userchrome.css);
in {
  programs.thunderbird = {
    enable = true;
    package = pkgs.thunderbird;
    profiles.default = {
      isDefault = true;
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "ui.systemUsesDarkTheme" = 1;

        # Keep message rendering aligned with the system-wide Stylix fonts.
        "font.name.monospace.x-western" = config.stylix.fonts.monospace.name;
        "font.name.sans-serif.x-western" = config.stylix.fonts.sansSerif.name;
        "font.name.serif.x-western" = config.stylix.fonts.serif.name;
        "font.size.variable.x-western" = 14;
        "font.size.fixed.x-western" = 14;

        # Layout: classic 3-pane
        "mail.pane_config.dynamic" = 1;
        # Compact density
        "mail.uiDensity" = 1;

        # Sort newest first
        "mailnews.default_sort_type" = 18;
        "mailnews.default_sort_order" = 2;

        # Plain text compose by default
        "mail.identity.default.compose_html" = false;
        "mail.compose.default_to_paragraph" = false;

        # Misc
        "browser.aboutConfig.showWarning" = false;
        "mail.phishing.detection.enabled" = true;
        "mail.spam.manualMark.biffAtStartup" = false;
      };
      userChrome = themedChrome;
    };
  };
}
