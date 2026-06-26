{pkgs, ...}: {
  programs.thunderbird = {
    enable = true;
    package = pkgs.thunderbird;
    profiles.default = {
      isDefault = true;
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "ui.systemUsesDarkTheme" = 1;

        # Fonts — match system JetBrainsMono config
        "font.name.monospace.x-western" = "JetBrainsMono Nerd Font Mono";
        "font.name.sans-serif.x-western" = "JetBrainsMono Nerd Font";
        "font.name.serif.x-western" = "JetBrainsMono Nerd Font";
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
      userChrome = builtins.readFile ./thunderbird-userchrome.css;
    };
  };
}
