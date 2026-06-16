{...}: {
  imports = [
    ./hardware.nix
    ../../nixos/webhost.nix
  ];

  networking.hostName = "bandit-lab";
  system.stateVersion = "25.11";
}
