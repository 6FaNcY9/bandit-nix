{
  pkgs,
  repoConfig,
  ...
}: {
  # ─── System fonts ─────────────────────────────────────
  fonts = {
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.iosevka-term
      nerd-fonts.jetbrains-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };

  # ─── Stylix — system-wide theming ─────────────────────
  stylix =
    repoConfig.mkStylixTheme pkgs
    // {
      targets = {
        gtk.enable = true;
        grub.enable = true;
        console.enable = true;
        # kmscon target sets removed nixpkgs options (extraConfig/fonts) — disable
        # until Stylix updates its kmscon module for the new API.
        kmscon.enable = false;
        qt.enable = true;
        plymouth.enable = true;
      };
    };
}
