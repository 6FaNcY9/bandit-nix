{
  lib,
  pkgs,
  modulesPath,
  atomicConsole,
  labCompose,
  ...
}: let
  # Guest ports forwarded to host loopback and allowed by the guest
  # firewall. The compose check in flake.nix asserts these stay published.
  labPorts = [8080 8888 8025];
in {
  imports = [
    (modulesPath + "/virtualisation/qemu-vm.nix")
    ./atomics.nix
    ./apps.nix
  ];
  networking.hostName = "security-lab";
  system.stateVersion = "25.11";
  services.getty.autologinUser = "root";
  virtualisation = {
    memorySize = 12288;
    cores = 4;
    diskSize = 40960;
    graphics = false;
    useNixStoreImage = true;
    sharedDirectories = lib.mkForce {};
    restrictNetwork = true;
    forwardPorts =
      map (port: {
        from = "host";
        host = {
          inherit port;
          address = "127.0.0.1";
        };
        guest.port = port;
      })
      labPorts;
    docker.enable = true;
  };
  networking.firewall.allowedTCPPorts = labPorts;
  environment.etc = {
    "security-lab/bloodhound.yml".source = ./stacks/bloodhound.yml;
    "security-lab/crapi.yml".source = ./stacks/crapi.yml;
  };
  environment.systemPackages = [labCompose atomicConsole pkgs.git pkgs.curl];
}
