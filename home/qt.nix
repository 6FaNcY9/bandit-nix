{
  config,
  pkgs,
  ...
}: {
  home = {
    packages = with pkgs; [
      libsForQt5.qtstyleplugin-kvantum
      libsForQt5.qt5ct
      qt6Packages.qt6ct
      qt6Packages.qtstyleplugin-kvantum
    ];

    # Stylix writes matching Qt 5/6 Kvantum configuration. Forcing qt6ct as the
    # platform theme globally breaks Qt 5 applications such as CopyQ and
    # Flameshot, so only select the cross-version Kvantum widget style here.
    sessionVariables.QT_STYLE_OVERRIDE = "kvantum";

    # Expose this profile's Kvantum/qtct style plugins to Qt apps from foreign
    # closures (nix profile, nix run): their wrappers only search their own
    # closure's plugin dirs, so without this they fall back to light Fusion.
    # Qt checks plugin ABI before loading, so a version mismatch degrades
    # gracefully to the app default rather than crashing.
    sessionSearchVariables.QT_PLUGIN_PATH = [
      "${config.home.profileDirectory}/lib/qt-6/plugins"
      "${config.home.profileDirectory}/lib/qt-5.15.19/plugins"
    ];
  };
}
