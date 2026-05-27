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
      dockerCompat = false; # use rootless podman directly; system socket is a container-escape vector
    };
    libvirtd.enable = true;
  };

  environment.systemPackages = with pkgs; [
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
    sops
  ];
}
