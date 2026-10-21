{
  lib,
  pkgs,
  ...
}: let
  # Same helper as homeConfigurations.vino; ci/theme-contract.nix asserts on it.
  stylixTheme = (import ../../lib/repository.nix {inherit lib;}).mkStylixTheme pkgs;
in {
  # ─── System fonts ─────────────────────────────────────
  fonts = {
    fontconfig.enable = true;
    packages = [
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.jetbrains-mono
      pkgs.noto-fonts
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-color-emoji
    ];
  };

  # ─── Stylix — system-wide theming ─────────────────────
  stylix =
    stylixTheme
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
