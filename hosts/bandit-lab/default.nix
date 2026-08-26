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
    ./searxng.nix
    ./changedetection.nix
    ./watchyourlan.nix
    ./power.nix
    ./auto-rebuild.nix
    ./health-check.nix
    # Sideloading is on hold (cable/hardware issues) — anisette.nix stays in
    # the repo but is not imported, so the service is not installed.
  ];

  networking.hostName = "bandit-lab";

  # Server: only root may ask the nix daemon to build/substitute. lab-update
  # already runs as root, so vino needs no trusted-user privilege here.
  nix.settings.trusted-users = lib.mkForce ["root"];

  # The lab's workloads (Docker, Traefik, PostgreSQL, Vaultwarden) use no
  # unprivileged eBPF; disable it. bpf_jit_harden stays off pending testing.
  boot.kernel.sysctl."kernel.unprivileged_bpf_disabled" = 1;

  services = {
    # Hardened defaults: longer escalating bans for repeat offenders.
    # The tailnet is exempt — Tailscale devices are already authenticated,
    # and a mistyped key there should never lock out the admin path.
    fail2ban = {
      enable = true;
      maxretry = 3;
      bantime = "1h";
      bantime-increment = {
        enable = true;
        maxtime = "1w";
        overalljails = true;
      };
      ignoreIP = ["100.64.0.0/10"];
    };

    openssh.settings = {
      PasswordAuthentication = lib.mkForce false;
      KbdInteractiveAuthentication = lib.mkForce false;
      PermitRootLogin = "no";
      # Only the vino account holds authorized keys; refuse everyone else
      # outright instead of relying on per-account key checks.
      AllowUsers = [repoConfig.workstation.username];
    };
  };

  users.users.${repoConfig.workstation.username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHOfT8hlUovvRJtHh5YKJzBhHZSK05WLGERQIq0H7GDt vino@bandit-homelab"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG23qu5Tr1aUKcJIetthXoavOQZd1IJqnp7wwffivJ2i phone@bandit-lab"
  ];

  system.stateVersion = "25.11";
}
