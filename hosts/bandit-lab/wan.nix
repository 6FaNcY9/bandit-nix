{config, ...}: {
  sops.secrets."cloudflare-tunnel-credentials" = {
    mode = "0400";
    # cloudflared reads its tunnel credentials when the process starts.
    restartUnits = ["cloudflared-tunnel-bandit-lab.service"];
  };

  # Outbound Cloudflare Tunnel — works through CGNAT.
  # IMPORTANT: this tunnel is REMOTELY MANAGED. The running cloudflared daemon
  # pulls its ingress config from the Zero Trust dashboard (Networks → Tunnels
  # → Public Hostnames) and ignores the local config file — it logged
  # "Updated to new configuration ... version=8" straight from the dashboard.
  # The ingress attrset below is a DOCUMENTATION MIRROR of the dashboard
  # routes, not the source of truth: to add/remove a hostname, edit the
  # dashboard (no rebuild needed, the daemon picks it up within seconds),
  # then update this list to match. Keep it default-deny: no wildcard route,
  # or any container with Traefik labels would be published instantly.
  # Cloudflare Access policies are configured outside this repository; see
  # docs/runbooks/cloudflare-access.md before publishing an admin service.
  services.cloudflared = {
    enable = true;
    tunnels."bandit-lab" = {
      credentialsFile = config.sops.secrets."cloudflare-tunnel-credentials".path;
      default = "http_status:404";
      ingress = {
        "bandit-lab.mrija.org" = "http://localhost:80";
        # AiiA AI T-shirt shop (Ghost fork) — deliberately public: a
        # storefront cannot sit behind a Cloudflare Access login. The Ghost
        # /ghost/ admin should get an
        # Access app if it ever needs hardening (docs/runbooks/cloudflare-access.md).
        "aiia.bandit-lab.mrija.org" = "http://localhost:80";
        # Primary storefront domain. Ghost canonical URL is https://aiia.at;
        # both hostnames route to the same Traefik service.
        "aiia.at" = "http://localhost:80";
        "www.aiia.at" = "http://localhost:80";
        "grafana.bandit-lab.mrija.org" = "http://localhost:80";
        "grafana.atmosphaere.at" = "http://localhost:80";
        "mail-archive.bandit-lab.mrija.org" = "http://localhost:80";
        # Canonical Vaultwarden hostname; the legacy public route was retired
        # after client migration verification.
        "vault.atmosphaere.at" = "http://localhost:80";
      };
    };
  };
}
