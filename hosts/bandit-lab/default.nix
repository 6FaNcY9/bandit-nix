{lib, ...}: {
  imports = [
    ./hardware.nix
    ./wan.nix
    ./webhost.nix
    ./traefik.nix
    ./mrija-archive.nix
    ./vaultwarden.nix
    ./power.nix
  ];

  networking.hostName = "bandit-lab";

  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce false;
    KbdInteractiveAuthentication = lib.mkForce false;
    PermitRootLogin = "no";
  };

  users.users.vino.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHOfT8hlUovvRJtHh5YKJzBhHZSK05WLGERQIq0H7GDt vino@bandit-homelab"
  ];

  system.stateVersion = "25.11";
}
