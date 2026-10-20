{
  config,
  lib,
  ...
}: let
  r = config.bandit.theme.roles;
  # :root custom properties from the palette roles; the CSS references them.
  roleVars = ":root {
" + lib.concatStrings (lib.mapAttrsToList (n: v: "  --b-${n}: ${v};
") r) + "}
";
  themedChrome = roleVars + builtins.readFile ./thunderbird-userchrome.css;
  markdownHereTokens = [
    "@canvas@"
    "@surface@"
    "@raised@"
    "@structure@"
    "@foreground@"
    "@critical@"
    "@active@"
    "@primary@"
    "@success@"
    "@info@"
    "@shadow@"
    "@secondary@"
    "@muted@"
  ];
  markdownHereColors = with r; [
    bg
    surface
    raised
    line
    fg
    crit
    warn
    accent
    ok
    info
    muted # shadow
    dim # secondary
    muted
  ];
  themedMarkdownHere = file:
    lib.replaceStrings
    markdownHereTokens
    markdownHereColors
    (builtins.readFile file);
in {
  programs.thunderbird = {
    enable = true;
    profiles.default = {
      isDefault = true;
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        # Follow Stylix polarity (1 = dark, 0 = light).
        "ui.systemUsesDarkTheme" =
          if config.stylix.polarity == "dark"
          then 1
          else 0;

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

  xdg.configFile = {
    "markdown-here-revival/chinatown-pixel-primary.css".text =
      themedMarkdownHere ./markdown-here-chinatown-primary.css;
    "markdown-here-revival/chinatown-pixel-syntax.css".text =
      themedMarkdownHere ./markdown-here-chinatown-syntax.css;
  };
}
