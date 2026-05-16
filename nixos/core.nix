{ pkgs, ... }:
{
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Vienna";

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      allowed-users = [ "vino" ];
      trusted-users = [ "root" "vino" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # ─── Fonts ────────────────────────────────────────────
  fonts = {
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
    ];
  };

  # ─── Stylix — system-wide theming ─────────────────────
  stylix = {
    enable = true;

    base16Scheme = {
      base00 = "262626";
      base01 = "3a3a3a";
      base02 = "4e4e4e";
      base03 = "8a8a8a";
      base04 = "949494";
      base05 = "dab997";
      base06 = "d5c4a1";
      base07 = "ebdbb2";
      base08 = "d75f5f";
      base09 = "ff8700";
      base0A = "ffaf00";
      base0B = "afaf00";
      base0C = "85ad85";
      base0D = "83adad";
      base0E = "d485ad";
      base0F = "d65d0e";
    };

    image = ../hosts/bandit/wallpaper.jpg;

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
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    targets = {
      gtk.enable = true;
      grub.enable = true;
    };
  };
}
