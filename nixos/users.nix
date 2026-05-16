{ pkgs, config, ... }:
{
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
    hashedPassword = "$6$..."; # run: mkpasswd -m sha-512
  };
}
