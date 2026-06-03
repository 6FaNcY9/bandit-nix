{pkgs, ...}: {
  # SSH server disabled — this machine only connects out, never accepts incoming.
  services.openssh.enable = false;

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    virt-manager.enable = true;
    nh = {
      enable = true;
      flake = "/home/vino/src/bandit-nix";
    };
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true; # use rootless podman directly; system socket is a container-escape vector
      autoPrune.enable = true; # Clean up dangling images/containers
    };
    libvirtd.enable = true;
  };

  # docker-compose CLI plugin is wired user-side via home.file in
  # home/shell.nix (~/.docker/cli-plugins/docker-compose). Docker CLI
  # discovers user plugins there, so no /usr/local pollution needed.

  environment.systemPackages = with pkgs; [
    docker-compose
    cachix
    git
    curl
    wget
    jq
    ripgrep
    fd
    bat
    eza
    gcc
    gnupg
    xclip
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
    comma
    lazygit
    sops
  ];
}
