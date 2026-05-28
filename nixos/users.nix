{
  pkgs,
  config,
  ...
}: {
  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    users.vino = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
        "audio"
        "video"
        "libvirtd"
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
