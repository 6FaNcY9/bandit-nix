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
  themedChrome = roleVars + builtins.readFile ./userchrome.css;
in {
  programs.firefox = {
    enable = true;
    # HM master moved the default under XDG configHome for stateVersion >=
    # 26.05; pin the legacy path so the existing profile is untouched.
    configPath = ".mozilla/firefox";
    profiles.default = {
      id = 0;
      isDefault = true;
      path = "0tfd3fet.default";
      extensions.force = true;

      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "browser.compactmode.show" = true;
        "browser.uidensity" = 1;
        "network.trr.mode" = 5; # disable built-in DoH; use system resolver (enforces our DoT policy)

        # Telemetry / studies / pocket / firefox-view shutdown
        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.policy.dataSubmissionEnabled" = false;
        "app.shield.optoutstudies.enabled" = false;
        "extensions.pocket.enabled" = false;
        "browser.tabs.firefox-view" = false;
        "browser.newtabpage.activity-stream.feeds.telemetry" = false;
        "browser.ping-centre.telemetry" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.server" = "data:,";
        "toolkit.telemetry.archive.enabled" = false;
        "toolkit.coverage.opt-out" = true;
        "toolkit.coverage.endpoint.base" = "";
      };

      userChrome = themedChrome;
    };
  };

  stylix.targets.firefox.profileNames = ["default"];

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      # Follow Stylix polarity so the light specialisation gets prefer-light.
      color-scheme = lib.mkForce (
        if config.stylix.polarity == "dark"
        then "prefer-dark"
        else "prefer-light"
      );
    };
  };
}
