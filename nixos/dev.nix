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

  # Wire docker-compose as a Docker CLI plugin so `docker compose` works with podman-dockerCompat
  system.activationScripts.dockerComposePlugin = {
    text = ''
      mkdir -p /usr/local/lib/docker/cli-plugins
      ln -sf ${pkgs.docker-compose}/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
    '';
    deps = [];
  };

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
    nix-index
    comma
    lazygit
    sops
  ];
}
