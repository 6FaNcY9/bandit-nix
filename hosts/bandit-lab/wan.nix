{config, ...}: {
  sops.secrets."cloudflare-tunnel-credentials" = {
    mode = "0400";
  };

  # Outbound Cloudflare Tunnel — works through CGNAT.
  # All traffic for bandit-lab.mrija.org and *.bandit-lab.mrija.org
  # routes to Traefik on :80 for container-based routing via labels.
  # Cloudflare Access policies are configured outside this repository; see
  # docs/runbooks/cloudflare-access.md before publishing an admin service.
  services.cloudflared = {
    enable = true;
    tunnels."bandit-lab" = {
      credentialsFile = config.sops.secrets."cloudflare-tunnel-credentials".path;
      default = "http_status:404";
      ingress = {
        # SSH must live outside the *.bandit-lab.mrija.org wildcard. The module
        # emits ingress rules via lib.attrNames (alphabetical), so "*" sorts
        # first and would match ssh.bandit-lab.mrija.org before any exact rule,
        # routing SSH to the Traefik HTTP origin. The hyphen keeps this
        # hostname out of the wildcard's suffix entirely.
        # Requires a Cloudflare Access application + policy in front of it;
        # see docs/runbooks/cloudflare-access.md.
        "ssh-bandit-lab.mrija.org" = "ssh://localhost:22";
        "bandit-lab.mrija.org" = "http://localhost:80";
        "*.bandit-lab.mrija.org" = "http://localhost:80";
      };
    };
  };
}
