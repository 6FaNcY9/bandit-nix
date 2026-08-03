{config, ...}: {
  sops.secrets."cloudflare-tunnel-credentials" = {
    mode = "0400";
  };

  # Outbound Cloudflare Tunnel — works through CGNAT.
  # Explicit per-hostname allowlist (default-deny): only the services below
  # reach Traefik on :80; every other subdomain under bandit-lab.mrija.org
  # falls through to the 404 default. Do NOT reintroduce a wildcard rule —
  # it would instantly publish any container that gets Traefik labels.
  # Cloudflare Access policies are configured outside this repository; see
  # docs/runbooks/cloudflare-access.md before publishing an admin service.
  services.cloudflared = {
    enable = true;
    tunnels."bandit-lab" = {
      credentialsFile = config.sops.secrets."cloudflare-tunnel-credentials".path;
      default = "http_status:404";
      ingress = {
        "bandit-lab.mrija.org" = "http://localhost:80";
        "grafana.bandit-lab.mrija.org" = "http://localhost:80";
        "mail.bandit-lab.mrija.org" = "http://localhost:80";
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
