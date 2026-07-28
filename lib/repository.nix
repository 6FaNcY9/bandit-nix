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

  workstationTheme = {
    name = "Chinatown Pixel";
    colors = {
      canvas = "#101915";
      surface = "#1B2525";
      raised = "#323B47";
      structure = "#3B413B";
      shadow = "#53556B";
      foreground = "#F3AB8B";
      muted = "#DB9673";
      primary = "#E96B59";
      active = "#D86531";
      secondary = "#D37887";
      critical = "#A4322E";
      success = "#8B9A63";
      info = "#6F849F";
    };
    geometry = {
      unit = 4;
      radius = 0;
      divider = 1;
      focus = 2;
      structure = 3;
    };
    fonts = {
      shell.name = "Departure Mono";
      technical.name = "IosevkaTerm Nerd Font Mono";
      interface.name = "Noto Sans";
    };
    icons.name = "Papirus-Dark";
    cursor = {
      name = "Bibata-Modern-Ice";
      size = 28;
    };
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
    base16Scheme = ../home/chinatown-pixel.yaml;
    polarity = "dark";
    image = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/AngelJumbo/gruvbox-wallpapers/main/wallpapers/pixelart/chinatown.png";
      hash = "sha256-IaQZb24eLpY49z3k1HnLAmbpucE93yhWyH7W8d/WI8g=";
    };
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.iosevka-term;
        name = "IosevkaTerm Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      sizes = {
        terminal = 14;
        applications = 14;
        desktop = 14;
        popups = 9;
      };
    };
    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 28;
    };
  };
}
