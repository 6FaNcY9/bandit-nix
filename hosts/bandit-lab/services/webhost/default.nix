# Homelab services for bandit-lab.
# Provides: server UI, PostgreSQL, Docker, Tailscale VPN, SMB storage.
# HTTP routing handled by Traefik (traefik.nix). TLS terminated by Cloudflare.
{
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
in {
  # bandit-lab: vino needs docker group for container management.
  # Keep server group scope tighter than the desktop laptop profile.
  users.users.${repoConfig.workstation.username}.extraGroups = lib.mkForce ["wheel" "networkmanager" "docker"];

  # ── Host paths ───────────────────────────────────────────────────────────
  systemd = {
    tmpfiles.rules = [
      # Root-owned: tmpfiles refuses to manage child dirs whose owner differs
      # from a non-root parent ("unsafe path transition"), which broke the
      # monitoring stack setup. Subdirs stay user-owned where declared.
      "d /srv/containers 0755 root root -"
      "d /srv/storage 0770 ${username} users -"
    ];

    # Cockpit is admin-only. Keep the systemd socket loopback-bound and access it via SSH/Tailscale tunnels.
    sockets.cockpit = {
      listenStreams = lib.mkForce [];
      socketConfig.ListenStream = lib.mkForce [
        ""
        "127.0.0.1:9090"
      ];
    };
    services = {
      # `tailscale set` only runs at activation, so a manual `tailscale set
      # --ssh` (or the admin console) would silently re-enable Tailscale SSH,
      # which bypasses OpenSSH, fail2ban and the firewall. Re-assert hourly.
      tailscaled-set.startAt = "hourly";
    };
  };

  # ── Server GUI ───────────────────────────────────────────────────────────
  services = {
    cockpit = {
      enable = true;
      allowed-origins = [
        "https://localhost:9090"
        "https://127.0.0.1:9090"
      ];
      openFirewall = false;
      plugins = with pkgs; [
        cockpit-files
      ];
    };

    # ── VPN ────────────────────────────────────────────────────────────────
    tailscale = {
      enable = true;
      # Use the hardened OpenSSH service over tailscale0. Tailscale SSH
      # intercepts port 22 and can lock out key-based access when its ACL
      # does not include an SSH rule.
      extraSetFlags = ["--ssh=false"];
    };

    # ── File storage ───────────────────────────────────────────────────────
    samba = {
      enable = true;
      openFirewall = false;
      # SMB is reached over the tailnet by address, so the NetBIOS name
      # service (UDP 137/138, LAN broadcast discovery) is not needed.
      nmbd.enable = false;
      settings = {
        global = {
          security = "user";
          "server string" = "bandit-lab";
          "map to guest" = "Bad User";
          # Legacy SMB1 has known remote-code-execution history; every
          # supported client speaks SMB2+.
          "server min protocol" = "SMB2";
          # Defense in depth behind the per-interface firewall: only loopback
          # and the tailnet (IPv4 and IPv6) may talk SMB. `hosts deny = ALL`,
          # not 0.0.0.0/0, which would leave every IPv6 client unmatched.
          "hosts allow" = "127.0.0.1 ::1 100.64.0.0/10 fd7a:115c:a1e0::/48";
          "hosts deny" = "ALL";
        };
        storage = {
          path = "/srv/storage";
          browseable = "yes";
          writable = "yes";
          "valid users" = username;
          "create mask" = "0660";
          "directory mask" = "0770";
        };
      };
    };

    # ── PostgreSQL ─────────────────────────────────────────────────────────
    postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      # NixOS defaults to Unix-socket access unless enableTCPIP is set.
      settings = {
        max_connections = 100;
        # The host has 64 GiB but Postgres shares it with Minecraft (12 GiB cap)
        # and Docker. Observed 2026-10-06 (before Wazuh was retired): about
        # 20 GiB used, about 43 GiB available, mostly page
        # cache shared by everything. effective_cache_size is only a planner
        # hint for how much of the data the OS cache can hold, so size it to a
        # realistic share, not to total RAM.
        shared_buffers = "2GB";
        effective_cache_size = "16GB";
        work_mem = "32MB";
      };
    };
  };

  # SMB is reachable over the tailnet only (decision D5, 2026-10-06): not on the
  # home Wi-Fi/LAN uplinks. WS-Discovery and NetBIOS are off because they only
  # advertise to the LAN; mount the share by tailnet address.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [139 445];

  # ── Docker ────────────────────────────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
    daemon.settings = {
      data-root = "/srv/containers/docker";
      log-driver = "local";
      live-restore = true;
      "icc" = false; # block inter-container comms by default
      "userland-proxy" = false; # use iptables hairpin NAT instead
    };
  };
  virtualisation.oci-containers.backend = "docker";

  environment.systemPackages = with pkgs; [
    cifs-utils
    docker-compose
    tailscale
  ];
}
