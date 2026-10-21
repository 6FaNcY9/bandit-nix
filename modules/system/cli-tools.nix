{pkgs, ...}: {
  # CLI tools used on both bandit and bandit-lab.
  # The lab still imports nixos/cli-tools.nix until phase 3; keep both in step.
  environment.systemPackages = [
    pkgs.git
    pkgs.curl
    pkgs.wget
    pkgs.jq
    pkgs.ripgrep
    pkgs.fd
    pkgs.bat
    pkgs.eza
    pkgs.gnupg
    pkgs.tree-sitter
    pkgs.gnumake
    pkgs.pkg-config
    pkgs.usbutils
    pkgs.pciutils
    pkgs.lm_sensors
    pkgs.alejandra
    pkgs.deadnix
    pkgs.statix
    pkgs.nix-output-monitor
    pkgs.nvd
    pkgs.sops
    pkgs.systemctl-tui
    pkgs.cachix
  ];
}
