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
      autoPrune.enable = true; # Clean up dangling images/containers
    };
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        swtpm.enable = true;
        vhostUserPackages = [pkgs.virtiofsd];
        verbatimConfig = ''
          memory_backing_dir = "/dev/shm"
        '';
      };
    };
    spiceUSBRedirection.enable = true;
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
    grc # fzf-tab-source: colorized ip/network output in previews
    lesspipe # fzf-tab-source: lets `less` preview archives/images/etc
    virtio-win # Windows virtio drivers ISO (mount in VM during install)
    win-spice # SPICE guest tools installer for Windows
  ];
}
