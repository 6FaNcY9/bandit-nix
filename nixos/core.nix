{pkgs, ...}: {
  # Allow unfree packages (e.g. firmware blobs, steam, vscode)
  nixpkgs.config.allowUnfree = true;
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Vienna";

  console = {
    keyMap = "de-latin1-nodeadkeys";
    font = "Lat2-Terminus16";
    earlySetup = true;
  };

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      auto-optimise-store = true;
      allowed-users = ["vino"];
      trusted-users = ["root"];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise = {
      automatic = true;
      dates = ["weekly"];
    };
  };

  # ─── Fonts ────────────────────────────────────────────
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
        terminal = 12;
        applications = 11;
        desktop = 11;
        popups = 11;
      };
    };

    cursor = {
      package = pkgs.capitaine-cursors;
      name = "capitaine-cursors";
      size = 24;
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

  services.journald.extraConfig = "SystemMaxUse=500M";
}
