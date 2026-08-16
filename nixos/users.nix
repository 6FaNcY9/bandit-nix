{
  pkgs,
  config,
  repoConfig,
  ...
}: {
  programs.fish.enable = true;
  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    users.${repoConfig.workstation.username} = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
        # Laptop-only groups (audio/video/libvirtd/adbusers) are appended by
        # nixos/dev.nix, which only bandit imports; bandit-lab declares its
        # own narrower list in hosts/bandit-lab/webhost.nix.
        # "input" removed — raw /dev/input/* access is a keylogging risk; acpilight uses video group
        # "storage" removed — raw block device r/w; udisks2 handles mount/unmount correctly
        # "podman" removed — not needed for rootless podman
      ];

      shell = pkgs.zsh;
      hashedPasswordFile = config.sops.secrets."user-password".path;
    };
  };

  security.sudo.wheelNeedsPassword = true; # default but explicit is better
}
