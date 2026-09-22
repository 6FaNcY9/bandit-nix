_: {
  # Private metasearch — daily-driver privacy service. Stateless on purpose:
  # the image entrypoint renders settings.yml (including a random secret_key)
  # into the container layer from env vars, so a recreate just rotates
  # sessions. No sops secret needed.
  virtualisation.oci-containers.containers.searxng = {
    image = "searxng/searxng@sha256:11a9b34cdc0b1ec2b991470a2762ecb5a1a531898289fb51dcd015260450729e";
    environment = {
      SEARXNG_BASE_URL = "https://search.bandit-lab.mrija.org/";
    };
    extraOptions = [
      "--network=proxy"
      "--label=traefik.enable=true"
      "--label=traefik.http.routers.searxng.rule=Host(`search.bandit-lab.mrija.org`)"
      "--label=traefik.http.routers.searxng.entrypoints=web"
      "--label=traefik.http.routers.searxng.middlewares=searxng-ratelimit"
      "--label=traefik.http.services.searxng.loadbalancer.server.port=8080"
      # Public endpoint: unthrottled metasearch abuse (scrapers proxying
      # through it) gets the host IP banned by upstream engines. Client IPs
      # resolve from Cloudflare's X-Forwarded-For (entrypoint trusts
      # cloudflared on loopback), so the limit keys on the real visitor.
      "--label=traefik.http.middlewares.searxng-ratelimit.ratelimit.average=60"
      "--label=traefik.http.middlewares.searxng-ratelimit.ratelimit.period=1m"
      "--label=traefik.http.middlewares.searxng-ratelimit.ratelimit.burst=120"
    ];
  };

  systemd.services.docker-searxng = {
    after = ["docker-network-proxy.service"];
    requires = ["docker-network-proxy.service"];
  };
}
