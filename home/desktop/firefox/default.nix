{lib, ...}: {
  programs.firefox = {
    enable = true;
    configPath = ".mozilla/firefox";
    profiles.default = {
      id = 0;
      isDefault = true;
      path = "0tfd3fet.default";

      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "browser.compactmode.show" = true;
        "browser.uidensity" = 1;
      };

      userChrome = builtins.readFile ./firefox-userchrome.css;
    };
  };

  stylix.targets.firefox.profileNames = ["default"];

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = lib.mkForce "prefer-dark";
    };
  };
}
