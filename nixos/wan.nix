{config, ...}: {
  sops.secrets."cloudflare-tunnel-credentials" = {
    mode = "0400";
  };

  services.cloudflared = {
    enable = true;
    tunnels."bandit-lab" = {
      credentialsFile = config.sops.secrets."cloudflare-tunnel-credentials".path;
      default = "http_status:404";
      ingress."bandit-lab.mrija.org" = "http://localhost:80";
    };
  };

  services.nginx.virtualHosts."bandit-lab.mrija.org" = {
    locations."/" = {
      return = "200 'bandit-lab online\n'";
      extraConfig = ''
        default_type text/plain;
      '';
    };
  };
}
