# Homelab services for bandit-lab.
# Provides: server UI, PostgreSQL, Docker + Portainer, Tailscale VPN, SMB storage.
# HTTP routing handled by Traefik (traefik.nix). TLS terminated by Cloudflare.
{pkgs, ...}: {
  # ── Host paths ───────────────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d /srv/containers 0750 vino users -"
    "d /srv/storage 0770 vino users -"
    "d /var/lib/portainer 0750 root root -"
  ];

  # ── Firewall ──────────────────────────────────────────────────────────────
  # Port 80 used by Traefik (tunnel connects locally, no external exposure needed).
  networking.firewall.allowedTCPPorts = [80];

  # ── Server GUI ───────────────────────────────────────────────────────────
  services.cockpit = {
    enable = true;
    openFirewall = false;
    plugins = with pkgs; [
      cockpit-files
    ];
  };

  # ── VPN ──────────────────────────────────────────────────────────────────
  services.tailscale.enable = true;

  # ── File storage ─────────────────────────────────────────────────────────
  services.samba = {
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
        "valid users" = "vino";
        "create mask" = "0660";
        "directory mask" = "0770";
      };
    };
  };
  services.samba-wsdd = {
    enable = true;
    openFirewall = false;
  };

  # ── PostgreSQL ────────────────────────────────────────────────────────────
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    settings = {
      max_connections = 100;
      shared_buffers = "4GB";
      effective_cache_size = "48GB";
      work_mem = "64MB";
    };
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
    };
  };
  virtualisation.oci-containers = {
    backend = "docker";
    containers.portainer = {
      image = "portainer/portainer-ce:lts";
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
  users.users.vino.extraGroups = ["docker"];

  environment.systemPackages = with pkgs; [
    cifs-utils
    docker-compose
    tailscale
  ];
}
