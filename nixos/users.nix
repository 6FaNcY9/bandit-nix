{ pkgs, ... }:
{
  users.mutableUsers = false;

  users.users.vino = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    shell = pkgs.fish;
  };
}
