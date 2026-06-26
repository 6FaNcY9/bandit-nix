{...}: {
  imports = [
    ./hardware.nix
    ./wan.nix
    ./webhost.nix
    ./traefik.nix
  ];

  networking.hostName = "bandit-lab";
  system.stateVersion = "25.11";
}
