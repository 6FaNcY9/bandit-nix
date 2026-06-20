{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    libsForQt5.qtstyleplugin-kvantum
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    qt6Packages.qtstyleplugin-kvantum
  ];

  # Stylix manages qt5ct/qt6ct/kvantum config files via qt module.
  # Force qt6ct (Stylix defaults to qt5ct) so Qt6 apps use the correct theme.
  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = lib.mkForce "qt6ct";
  };
}
