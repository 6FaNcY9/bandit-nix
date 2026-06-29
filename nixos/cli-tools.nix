{pkgs, ...}: {
  # CLI tools used on both bandit and bandit-lab.
  # Import from nixos/default.nix (laptop) and nixos/server.nix (server).
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    jq
    ripgrep
    fd
    bat
    eza
    gnupg
    tree-sitter
    gnumake
    pkg-config
    usbutils
    pciutils
    lm_sensors
    alejandra
    deadnix
    statix
    nix-output-monitor
    nvd
    sops
    cachix
  ];
}
