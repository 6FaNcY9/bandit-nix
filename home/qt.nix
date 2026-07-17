{pkgs, ...}: {
  home.packages = with pkgs; [
    libsForQt5.qtstyleplugin-kvantum
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    qt6Packages.qtstyleplugin-kvantum
  ];

  # Stylix writes matching Qt 5/6 Kvantum configuration. Forcing qt6ct as the
  # platform theme globally breaks Qt 5 applications such as CopyQ and
  # Flameshot, so only select the cross-version Kvantum widget style here.
  home.sessionVariables.QT_STYLE_OVERRIDE = "kvantum";
}
