{
  lib,
  repoConfig,
  ...
}: {
  imports = [
    ./hardware.nix
    ./services/cockpit-theme
    ./wan.nix
    ./services/webhost
    ./services/traefik
    ./services/mrija-archive
    ./services/monitoring
    ./services/beszel
    ./services/vaultwarden
    ./services/searxng
    ./services/watchyourlan
    ./services/minecraft
    ./power.nix
    ./services/aiia
    ./services/auto-rebuild
    ./services/crowdsec
    ./services/wazuh
    ./services/toolbox
    ./services/health-check
    ./services/backup
    # Sideloading is on hold (cable/hardware issues) — services/anisette stays
    # in the repo but is not imported, so the service is not installed.
  ];

  networking.hostName = "bandit-lab";

  # The lab's workloads (Docker, Traefik, PostgreSQL, Vaultwarden) use no
  # unprivileged eBPF; disable it. bpf_jit_harden stays off pending testing.
  boot.kernel.sysctl."kernel.unprivileged_bpf_disabled" = 1;

  services = {
    # Stable server uplink: fail closed if the configured public resolvers
    # cannot use TLS. Tailscale's per-link split DNS is configured separately.
    resolved.settings.Resolve = {
      DNSOverTLS = lib.mkForce "true";
      # No LAN name-resolution protocols on a server (listened on every
      # interface: 5355 LLMNR, 5353 mDNS).
      LLMNR = "false";
      MulticastDNS = "false";
    };

    # Local recovery copies only; off-host backups still need a destination.
    # The native module retains the current and previous successful dump.
    postgresqlBackup = {
      enable = true;
      backupAll = true;
      startAt = "*-*-* 03:15:00";
    };

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
      # Only the vino account holds authorized keys; refuse everyone else
      # outright instead of relying on per-account key checks.
      AllowUsers = [repoConfig.workstation.username];
    };
  };

  # The metadata refresh failed ("PolicyKit daemon is not available") when it
  # fired while a switch had polkit stopped, and lab-update then rolled the whole
  # deploy back. Firmware on the lab is updated by hand, so the timer is not needed.
  systemd.timers.fwupd-refresh.enable = false;

  users.users.${repoConfig.workstation.username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHOfT8hlUovvRJtHh5YKJzBhHZSK05WLGERQIq0H7GDt vino@bandit-homelab"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG23qu5Tr1aUKcJIetthXoavOQZd1IJqnp7wwffivJ2i phone@bandit-lab"
  ];

  system.stateVersion = "25.11";
}
