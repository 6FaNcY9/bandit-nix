{lib}: let
  unfreePackageNames = [
    "cheatsheet.nvim"
    "nvidia-kernel-modules"
    "nvidia-persistenced"
    "nvidia-settings"
    "nvidia-x11"
  ];
in {
  system = "x86_64-linux";

  workstation = {
    username = "vino";
    homeDirectory = "/home/vino";
    repoPath = "/home/vino/src/bandit-nix";
  };

  # Shared with the headless shell and editor modules.
  serverPalette = {
    base00 = "#282828";
    base01 = "#3c3836";
    base02 = "#504945";
    base03 = "#928374";
    base04 = "#a89984";
    base05 = "#d5c4a1";
    base06 = "#ebdbb2";
    base07 = "#fbf1c7";
    base08 = "#cc241d";
    base09 = "#d65d0e";
    base0A = "#d79921";
    base0B = "#98971a";
    base0C = "#689d6a";
    base0D = "#458588";
    base0E = "#b16286";
    base0F = "#d65d0e";
  };

  inherit unfreePackageNames;

  allowUnfreePredicate = pkg: let
    name = lib.getName pkg;
  in
    builtins.elem name unfreePackageNames
    # Ollama requires the CUDA runtime/toolchain closure, whose package names
    # are versioned independently by nixpkgs.
    || lib.hasPrefix "cuda_" name
    || lib.hasPrefix "libcu" name;

  mkStylixTheme = pkgs: {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark.yaml";
    image = ../hosts/bandit/wallpaper.png;
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
        terminal = 14;
        applications = 14;
        desktop = 14;
        popups = 11;
      };
    };
    cursor = {
      package = pkgs.openzone-cursors;
      name = "OpenZone_Black_Slim";
      size = 30;
    };
  };
}
