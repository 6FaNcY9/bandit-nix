# Homelab services for bandit-lab.
# Provides: server UI, PostgreSQL, Docker + Portainer, Tailscale VPN, SMB storage.
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
      "d /var/lib/portainer 0750 root root -"
    ];

    # Cockpit is admin-only. Keep the systemd socket loopback-bound and access it via SSH/Tailscale tunnels.
    sockets.cockpit = {
      listenStreams = lib.mkForce [];
      socketConfig.ListenStream = lib.mkForce [
        ""
        "127.0.0.1:9090"
      ];
    };
    services.docker-portainer = {
      after = ["docker-network-proxy.service"];
      requires = ["docker-network-proxy.service"];
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
      extraSetFlags = ["--ssh"];
    };

    # ── File storage ───────────────────────────────────────────────────────
    samba = {
      enable = true;
      openFirewall = false;
      settings = {
        global = {
          security = "user";
          "server string" = "bandit-lab";
          "map to guest" = "Bad User";
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

    samba-wsdd = {
      enable = true;
      openFirewall = false;
      interface = "enp44s0";
    };

    # ── PostgreSQL ─────────────────────────────────────────────────────────
    postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      # NixOS defaults to Unix-socket access unless enableTCPIP is set.
      settings = {
        max_connections = 100;
        shared_buffers = "4GB";
        effective_cache_size = "48GB";
        work_mem = "64MB";
      };
    };
  };

  networking.firewall.interfaces."enp44s0" = {
    # LAN file sharing is intentional; WAN service exposure stays behind Cloudflare Tunnel/Tailscale.
    allowedTCPPorts = [139 445 5357]; # SMB + WSDD
    allowedUDPPorts = [137 138 3702]; # NetBIOS + WSDD
  };

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
  virtualisation.oci-containers = {
    backend = "docker";
    containers.portainer = {
      image = "portainer/portainer-ce:2.39.6@sha256:3fa8750ac2b98ce56784ca292df1adc3ec38f0062fd572811ea4b2221beee310";
      # WAN-published through Traefik + Cloudflare Tunnel, gated by a
      # Cloudflare Access application (docs/runbooks/cloudflare-access.md).
      # Loopback HTTPS stays available: ssh -L 9443:localhost:9443 bandit-lab.
      ports = ["127.0.0.1:9443:9443"];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "/var/lib/portainer:/data"
      ];
      extraOptions = [
        "--network=proxy"
        "--label=traefik.enable=true"
        "--label=traefik.http.routers.portainer.rule=Host(`portainer.bandit-lab.mrija.org`)"
        "--label=traefik.http.routers.portainer.entrypoints=web"
        "--label=traefik.http.services.portainer.loadbalancer.server.port=9000"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    cifs-utils
    docker-compose
    tailscale
  ];
}
