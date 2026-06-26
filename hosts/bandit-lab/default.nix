{...}: {
  imports = [
    ./hardware.nix
    ../../nixos/wan.nix
    ../../nixos/webhost.nix
    ../../nixos/traefik.nix
  ];

  networking.hostName = "bandit-lab";
  system.stateVersion = "25.11";
}
