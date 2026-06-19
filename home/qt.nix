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

  xdg.configFile = {
    "Kvantum/kvantum.kvconfig".text = ''
      [General]
      theme=KvDark
    '';
    "qt5ct/qt5ct.conf".text = ''
      [Appearance]
      style=kvantum-dark
      color_scheme_path=
      custom_palette=false
      standard_dialogs=default
    '';
    "qt6ct/qt6ct.conf".text = ''
      [Appearance]
      style=kvantum-dark
      color_scheme_path=
      custom_palette=false
      standard_dialogs=default
    '';
  };

  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_STYLE_OVERRIDE = lib.mkForce "kvantum-dark";
  };
}
