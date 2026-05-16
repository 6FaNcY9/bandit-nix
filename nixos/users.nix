{ pkgs, ... }:
{
  programs.fish.enable = true;

  users.mutableUsers = false;

  users.users.vino = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "input"
      "storage"
    ];

    shell = pkgs.fish;
    # temporary until sops is configured — replace with hashedPasswordFile
    hashedPassword = "$6$w/id8WONcOVFgaLH$Y92T1W3/n6pNy5bXYv7M8pyAqa6f1kpskszGXort4pjy3nDJW3ZN.1cdZpHwHab3huKNWNWLWPw9ZxkaAO4fK"; # run: mkpasswd -m sha-512
  };

  security.sudo.wheelNeedsPassword = true;  # default but explicit is better
}
