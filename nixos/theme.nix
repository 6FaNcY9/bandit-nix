{
  config,
  lib,
  pkgs,
  repoConfig,
  ...
}: {
  options.bandit.themeVariant = lib.mkOption {
    type = lib.types.enum ["dark" "light"];
    default = "dark";
    description = "Palette variant (themes/palette.nix); the light boot specialisation sets \"light\".";
  };

  config = {
    fonts = {
      fontconfig.enable = true;
      packages = with pkgs; [
        nerd-fonts.fira-code
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];
    };

    stylix =
      repoConfig.mkStylixTheme pkgs config.bandit.themeVariant
      // {
        targets = {
          gtk.enable = true;
          grub.enable = true;
          console.enable = true;
          # Stylix's kmscon module still sets options removed from nixpkgs.
          kmscon.enable = false;
          qt.enable = true;
          plymouth.enable = true;
        };
      };
  };
}
