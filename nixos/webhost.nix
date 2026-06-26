# Homelab services for bandit-lab.
# Provides: server UI, nginx reverse proxy, ACME, PostgreSQL, containers,
# Tailscale VPN, and a simple SMB storage share.
{pkgs, ...}: {
  # ── Host paths ───────────────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d /srv/containers 0750 vino users -"
    "d /srv/storage 0770 vino users -"
    "d /var/lib/portainer 0750 root root -"
  ];

  # ── Firewall ──────────────────────────────────────────────────────────────
  networking.firewall.allowedTCPPorts = [80 443];

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

  # ── ACME / Let's Encrypt ──────────────────────────────────────────────────
  security.acme = {
    acceptTerms = true;
    defaults.email = "vinobandit@ik.me";
  };

  # ── Nginx ─────────────────────────────────────────────────────────────────
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Add virtualHosts per project, e.g.:
    # virtualHosts."example.com" = {
    #   enableACME = true;
    #   forceSSL = true;
    #   locations."/" = { proxyPass = "http://127.0.0.1:3000"; };
    # };
  };

  # ── PostgreSQL ────────────────────────────────────────────────────────────
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    settings = {
      max_connections = 100;
      shared_buffers = "4GB"; # ~6% of 64 GB RAM
      effective_cache_size = "48GB";
      work_mem = "64MB";
    };
  };

  # ── Docker (for containerised client projects) ────────────────────────────
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
    };
  };
  users.users.vino.extraGroups = ["docker"];

  environment.systemPackages = with pkgs; [
    cifs-utils
    docker-compose
    tailscale
  ];
}
