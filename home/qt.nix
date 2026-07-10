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
  # QT_STYLE_OVERRIDE is required too — qt6ct.conf sets style=kvantum, but
  # without this env var Qt falls back to Fusion and Kvantum never renders
  # (confirmed via live qt6ct screenshot: "Color scheme" preview was blank).
  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = lib.mkForce "qt6ct";
    QT_STYLE_OVERRIDE = "kvantum";
  };
}
