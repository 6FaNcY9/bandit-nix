{config, ...}: {
  # Public hostname for the lab server.
  # Cloudflare token secret must contain:
  #   CLOUDFLARE_API_TOKEN=...
  services.cloudflare-ddns = {
    enable = true;
    credentialsFile = config.sops.secrets."cloudflare-ddns-env".path;
    domains = ["bandit-lab.mrija.org"];
    proxied = "true";
    ttl = 1;
    updateOnStart = true;
    updateCron = "@every 5m";
    recordComment = "Managed by bandit-nix services.cloudflare-ddns";
  };

  services.nginx.virtualHosts."bandit-lab.mrija.org" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      return = "200 'bandit-lab online\n'";
      extraConfig = ''
        default_type text/plain;
      '';
    };
  };
}
