{ ... }:
{
  imports = [
    ./hardware.nix
  ];

  networking.hostName = "bandit";
  system.stateVersion = "25.11";
}
