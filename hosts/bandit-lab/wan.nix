{config, ...}: {
  sops.secrets."cloudflare-tunnel-credentials" = {
    mode = "0400";
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
        # AiiA AI T-shirt shop (Ghost fork) — deliberately public, like
        # vault.bandit-lab.mrija.org: a storefront cannot sit behind a
        # Cloudflare Access login. The Ghost /ghost/ admin should get an
        # Access app if it ever needs hardening (docs/runbooks/cloudflare-access.md).
        "aiia.bandit-lab.mrija.org" = "http://localhost:80";
        # WatchYourLAN device inventory — must have a Cloudflare Access
        # application (docs/runbooks/cloudflare-access.md); it has no auth
        # of its own and the host list is sensitive network metadata.
        "devices.bandit-lab.mrija.org" = "http://localhost:80";
        "grafana.bandit-lab.mrija.org" = "http://localhost:80";
        "mail-archive.bandit-lab.mrija.org" = "http://localhost:80";
        # Admin UI — must have a Cloudflare Access application in front of it
        # (docs/runbooks/cloudflare-access.md); never expose it directly.
        "portainer.bandit-lab.mrija.org" = "http://localhost:80";
        # Metasearch — needs a Cloudflare Access application
        # (docs/runbooks/cloudflare-access.md). A public SearXNG instance
        # gets scraped/abused by bots within hours.
        "search.bandit-lab.mrija.org" = "http://localhost:80";
        # Requires a Cloudflare Access application + policy in front of it;
        # see docs/runbooks/cloudflare-access.md.
        "ssh-bandit-lab.mrija.org" = "ssh://localhost:22";
        # Vaultwarden stays without an Access app: native Bitwarden clients
        # cannot complete an interactive Access login.
        "vault.bandit-lab.mrija.org" = "http://localhost:80";
      };
    };
  };
}
