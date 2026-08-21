{
  lib,
  repoConfig,
  ...
}: {
  imports = [
    ./hardware.nix
    ./cockpit-theme.nix
    ./wan.nix
    ./webhost.nix
    ./traefik.nix
    ./mrija-archive.nix
    ./monitoring.nix
    ./vaultwarden.nix
    ./power.nix
    ./auto-rebuild.nix
    ./health-check.nix
    # Ollama is temporarily parked. Keep llm.nix and its dependent
    # log-monitor.nix in the repo so the service can be restored later without
    # deleting /srv/ollama or its models.
    # Sideloading is on hold (cable/hardware issues) — anisette.nix stays in
    # the repo but is not imported, so the service is not installed.
  ];

  networking.hostName = "bandit-lab";

  services = {
    fail2ban.enable = true;

    openssh.settings = {
      PasswordAuthentication = lib.mkForce false;
      KbdInteractiveAuthentication = lib.mkForce false;
      PermitRootLogin = "no";
    };
  };

  users.users.${repoConfig.workstation.username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHOfT8hlUovvRJtHh5YKJzBhHZSK05WLGERQIq0H7GDt vino@bandit-homelab"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG23qu5Tr1aUKcJIetthXoavOQZd1IJqnp7wwffivJ2i phone@bandit-lab"
  ];

  system.stateVersion = "25.11";
}
