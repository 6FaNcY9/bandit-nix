{pkgs, config, ...}: {
  programs.fish.enable = true;

  users = {
    mutableUsers = false;
    users.vino = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
        "audio"
        "video"
        "input"
        "storage"
        "libvirtd"
        "podman"
      ];

      shell = pkgs.fish;
      hashedPasswordFile = config.sops.secrets."user-password".path;
    };
  };

  security.sudo.wheelNeedsPassword = true; # default but explicit is better
}
