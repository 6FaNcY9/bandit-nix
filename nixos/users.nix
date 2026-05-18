{
  pkgs,
  ...
}: {
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
      hashedPassword = "$6$w/id8WONcOVFgaLH$Y92T1W3/n6pNy5bXYv7M8pyAqa6f1kpskszGXort4pjy3nDJW3ZN.1cdZpHwHab3huKNWNWLWPw9ZxkaAO4fK";
    };
  };

  security.sudo.wheelNeedsPassword = true; # default but explicit is better
}
