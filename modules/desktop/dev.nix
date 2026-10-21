{
  pkgs,
  config,
  ...
}: {
  # SSH server disabled — this machine only connects out, never accepts incoming.
  services.openssh.enable = false;

  # Laptop-only user groups (VMs, audio, adb) — declared next to the tooling
  # that needs them; see modules/system/users.nix for the base set shared with
  # bandit-lab.
  users.users.${config.bandit.workstation.username}.extraGroups = [
    "audio"
    "video"
    "libvirtd"
    "adbusers"
  ];

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    virt-manager.enable = true;
    nh = {
      enable = true;
      flake = config.bandit.workstation.repoPath;
    };
  };

  virtualisation = {
    docker.rootless = {
      enable = true;
      # Point the Docker CLI at the per-user daemon. This provides sudo-less
      # Docker without granting root-equivalent access through the docker group.
      setSocketVariable = true;
    };
    podman = {
      enable = true;
      # Keep the existing Podman storage/runtime available without shadowing
      # the Docker CLI provided by rootless Docker.
      dockerCompat = false;
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
  # modules/user/terminal/tools.nix (~/.config/docker/cli-plugins/docker-compose).
  # Docker CLI discovers user plugins there, so no /usr/local pollution needed.

  environment.systemPackages = [
    pkgs.gcc
    pkgs.devenv
    pkgs.comma
    pkgs.lazygit
    pkgs.grc # fzf-tab-source: colorized ip/network output in previews
    pkgs.lesspipe # fzf-tab-source: lets `less` preview archives/images/etc
    pkgs.virtio-win # Windows virtio drivers ISO (mount in VM during install)
    pkgs.win-spice # SPICE guest tools installer for Windows
  ];
}
