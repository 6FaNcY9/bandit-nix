{
  config,
  pkgs,
  ...
}: {
  programs.fish.enable = true;

  sops.secrets."users/vino/password" = {
    sopsFile = ../secrets/secrets.yaml;
    neededForUsers = true;
  };

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
      hashedPasswordFile = config.sops.secrets."users/vino/password".path;
    };
  };

  security.sudo.wheelNeedsPassword = true; # default but explicit is better
}
