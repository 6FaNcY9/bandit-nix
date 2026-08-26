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
      "--label=traefik.http.services.searxng.loadbalancer.server.port=8080"
    ];
  };

  systemd.services.docker-searxng = {
    after = ["docker-network-proxy.service"];
    requires = ["docker-network-proxy.service"];
  };
}
