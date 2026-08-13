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
  ensurePortainerControlNetwork = pkgs.writeShellScript "ensure-portainer-control-network" ''
    set -euo pipefail

    network_state="$(${pkgs.docker}/bin/docker network inspect --format '{{.Internal}}' portainer-control 2>/dev/null || true)"
    case "$network_state" in
      true) ;;
      "")
        ${pkgs.docker}/bin/docker network create --internal portainer-control
        ;;
      *)
        echo "Docker network portainer-control exists but is not internal" >&2
        exit 1
        ;;
    esac
  '';
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
    services = {
      docker-network-portainer-control = {
        description = "Create the private Portainer control network";
        after = ["docker.service"];
        requires = ["docker.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = ensurePortainerControlNetwork;
        };
      };
      docker-portainer = {
        after = [
          "docker-network-portainer-control.service"
          "docker-network-proxy.service"
        ];
        requires = [
          "docker-network-portainer-control.service"
          "docker-network-proxy.service"
        ];
      };
      docker-portainer-agent = {
        after = ["docker-network-portainer-control.service"];
        requires = ["docker-network-portainer-control.service"];
      };
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
    containers = {
      portainer = {
        image = "portainer/portainer-ee:2.39.6@sha256:00c8114f44e240b4aa14429d365c1fb05cf7cd163ab0601c084c7af6ce8d58e2";
        # WAN-published through Traefik + Cloudflare Tunnel, gated by a
        # Cloudflare Access application (docs/runbooks/cloudflare-access.md).
        # Loopback HTTPS stays available: ssh -L 9443:localhost:9443 bandit-lab.
        ports = ["127.0.0.1:9443:9443"];
        volumes = [
          # Keep the direct socket only until the local environment is migrated
          # to the Agent, then remove it in a follow-up deployment.
          "/var/run/docker.sock:/var/run/docker.sock"
          "/var/lib/portainer:/data"
        ];
        extraOptions = [
          "--network=proxy"
          "--network=portainer-control"
          "--label=traefik.enable=true"
          "--label=traefik.http.routers.portainer.rule=Host(`portainer.bandit-lab.mrija.org`)"
          "--label=traefik.http.routers.portainer.entrypoints=web"
          "--label=traefik.http.services.portainer.loadbalancer.server.port=9000"
        ];
      };

      "portainer-agent" = {
        image = "portainer/agent:2.39.6@sha256:98bbc9d39f415fe917723999c8db0fef66f2f2f00a76230fab0b01f7fa782ff6";
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock"
          "/srv/containers/docker/volumes:/var/lib/docker/volumes"
          "/:/host"
        ];
        # Only Portainer shares this internal network with the Agent; no host
        # or firewall port is exposed.
        extraOptions = ["--network=portainer-control"];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    cifs-utils
    docker-compose
    tailscale
  ];
}
