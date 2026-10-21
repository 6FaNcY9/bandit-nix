{pkgs, ...}: let
  # Workstation Stylix theme. The standalone homeConfigurations.vino still
  # takes the same values from lib/repository.nix mkStylixTheme; keep in step.
  stylixTheme = {
    enable = true;
    base16Scheme = ../../themes/gruvbox-dark.yaml;
    polarity = "dark";
    image = ../../themes/gruvbox_minimal_space.png;
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font";
      };
      serif = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font";
      };
      sizes = {
        terminal = 18;
        applications = 18;
        desktop = 18;
        # Was 10 — rofi/mako/tooltip text was barely readable on the
        # Framework 13's high-DPI panel at scale 1.
        popups = 14;
      };
    };
    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 20;
    };
  };
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
