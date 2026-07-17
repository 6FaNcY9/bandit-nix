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
    base00 = "#111111";
    base01 = "#1b1d1e";
    base02 = "#2d2d2d";
    base03 = "#6c7070";
    base04 = "#a7a9a5";
    base05 = "#d8d8c8";
    base06 = "#eee8d5";
    base07 = "#fff8dc";
    base08 = "#f2777a";
    base09 = "#f99157";
    base0A = "#ffcc66";
    base0B = "#99cc99";
    base0C = "#66cccc";
    base0D = "#6699cc";
    base0E = "#cc99cc";
    base0F = "#d27b53";
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
    base16Scheme = ../home/bandit-retro.yaml;
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
