# Web hosting module — import from hosts/bandit-lab/default.nix when ready.
# Provides: nginx reverse proxy, ACME/Let's Encrypt, PostgreSQL.
{pkgs, ...}: {
  # ── Firewall ──────────────────────────────────────────────────────────────
  networking.firewall.allowedTCPPorts = [80 443];

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
    autoPrune.enable = true;
  };
  users.users.vino.extraGroups = ["docker"];
}
