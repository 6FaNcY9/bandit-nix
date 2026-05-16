{ ... }:
{
  imports = [
    ./hardware.nix
    ../../nixos/core.nix
    ../../nixos/boot.nix
    ../../nixos/network.nix
    ../../nixos/audio.nix
    ../../nixos/desktop.nix
    ../../nixos/users.nix
  ];

  networking.hostName = "bandit";
  system.stateVersion = "24.11";
}
