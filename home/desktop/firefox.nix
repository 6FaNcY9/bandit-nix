{lib, ...}: {
  programs.firefox = {
    enable = true;
    profiles.default = {
      id = 0;
      isDefault = true;
      # Point to the existing profile dir so Firefox data is preserved across rebuilds.
      # Without this HM creates a fresh empty profile and Firefox appears to "reset".
      path = "0tfd3fet.default";
    };
  };

  stylix.targets.firefox.profileNames = ["default"];

  # Workaround for stylix/issues/2071: Firefox ignores userChrome.css theming
  # when xdg-desktop-portal-gtk is active because the portal reads dconf
  # color-scheme instead of the GTK theme name. Setting prefer-dark forces it
  # to pick up the dark GTK theme Stylix installed.
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = lib.mkForce "prefer-dark";
    };
  };
}
