{lib, ...}: {
  programs.firefox = {
    enable = true;
    profiles.default = {
      id = 0;
      isDefault = true;
    };
  };

  stylix.targets.firefox.profileNames = [ "default" ];

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
