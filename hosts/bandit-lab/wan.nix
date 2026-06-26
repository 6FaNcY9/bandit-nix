{config, ...}: {
  sops.secrets."cloudflare-tunnel-credentials" = {
    mode = "0400";
  };

  # Outbound Cloudflare Tunnel — works through CGNAT.
  # All traffic for bandit-lab.mrija.org and *.bandit-lab.mrija.org
  # routes to Traefik on :80 for container-based routing via labels.
  services.cloudflared = {
    enable = true;
    tunnels."bandit-lab" = {
      credentialsFile = config.sops.secrets."cloudflare-tunnel-credentials".path;
      default = "http_status:404";
      ingress = {
        "bandit-lab.mrija.org" = "http://localhost:80";
        "*.bandit-lab.mrija.org" = "http://localhost:80";
      };
    };
  };
}
