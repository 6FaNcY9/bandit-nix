{lib}: let
  unfreePackageNames = [
    "cheatsheet.nvim"
    "nvidia-kernel-modules"
    "nvidia-persistenced"
    "nvidia-settings"
    "obsidian"
    "nvidia-x11"
    "copilot-language-server"
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
    name = "Gruvbox";
    colors = {
      canvas = "#282828";
      surface = "#3c3836";
      raised = "#504945";
      structure = "#665c54";
      shadow = "#7c6f64";
      foreground = "#ebdbb2";
      muted = "#bdae93";
      primary = "#fe8019";
      active = "#d65d0e";
      secondary = "#d3869b";
      critical = "#fb4934";
      success = "#b8bb26";
      info = "#83a598";
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
      technical.name = "JetBrainsMono Nerd Font Mono";
      interface.name = "Noto Sans";
    };
    icons.name = "Papirus-Dark";
    cursor = {
      name = "Bibata-Modern-Ice";
      size = 20;
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
    base16Scheme = ../themes/gruvbox-dark.yaml;
    polarity = "dark";
    image = ../themes/gruvbox_minimal_space.png;
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
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
}
