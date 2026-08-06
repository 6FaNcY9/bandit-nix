{
  config,
  lib,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;
  themedChrome =
    lib.replaceStrings
    ["#282828" "#1d2021" "#3c3836" "#504945" "#928374" "#d5c4a1" "#d79921" "#458588" "#cc241d"]
    [colors.base00 colors.base01 colors.base01 colors.base02 colors.base03 colors.base05 colors.base0A colors.base0C colors.base08]
    (builtins.readFile ./userchrome.css);
in {
  programs.firefox = {
    enable = true;
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
