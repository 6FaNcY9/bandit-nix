{pkgs, ...}: {
  # CLI tools used on both bandit and bandit-lab.
  # Imported by both hosts: modules/system/default.nix (laptop) and modules/server/default.nix (lab).
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
