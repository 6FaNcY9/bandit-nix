{pkgs, ...}: {
  # ─── System fonts ─────────────────────────────────────
  fonts = {
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };

  # ─── Stylix — system-wide theming ─────────────────────
  stylix = {
    enable = true;

    base16Scheme = "${pkgs.base16-schemes}/share/themes/tomorrow-night-eighties.yaml";

    image = "${pkgs.nixos-artwork.wallpapers.nineish-dark-gray}/share/wallpapers/nineish-dark-gray/contents/images/nix-wallpaper-nineish-dark-gray.png";

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      serif = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sizes = {
        terminal = 16;
        applications = 16;
        desktop = 16;
        popups = 12;
      };
    };

    cursor = {
      package = pkgs.capitaine-cursors;
      name = "capitaine-cursors";
      size = 26;
    };

    targets = {
      gtk.enable = true;
      grub.enable = true;
      console.enable = true;
      lightdm.enable = true;
      # kmscon target sets removed nixpkgs options (extraConfig/fonts) — disable
      # until Stylix updates its kmscon module for the new API.
      kmscon.enable = false;
    };
  };
}
