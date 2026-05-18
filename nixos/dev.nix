{pkgs, ...}: {
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    virt-manager.enable = true;
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
    };
    libvirtd.enable = true;
  };

  environment.systemPackages = with pkgs; [
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
  ];
}
