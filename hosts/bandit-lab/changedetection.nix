{repoConfig, ...}: let
  username = repoConfig.workstation.username;
in {
  systemd.tmpfiles.rules = [
    "d /srv/containers/changedetection 0750 ${username} users -"
    "d /srv/containers/changedetection/data 0750 ${username} users -"
  ];

  # Website change monitoring. Uses the built-in plaintext fetcher; the
  # optional Playwright browser endpoint (browser steps / JS-heavy pages) is
  # deliberately not deployed — add a browserless container if ever needed.
  virtualisation.oci-containers.containers.changedetection = {
    image = "dgtlmoon/changedetection.io@sha256:5438423d5e906eff4e8f7886823482ad23f472bf7b8530ccaca89fb48c337882";
    volumes = [
      "/srv/containers/changedetection/data:/datastore"
    ];
    extraOptions = [
      "--network=proxy"
      "--label=traefik.enable=true"
      "--label=traefik.http.routers.changedetection.rule=Host(`changes.bandit-lab.mrija.org`)"
      "--label=traefik.http.routers.changedetection.entrypoints=web"
      "--label=traefik.http.services.changedetection.loadbalancer.server.port=5000"
    ];
  };

  systemd.services.docker-changedetection = {
    after = ["docker-network-proxy.service"];
    requires = ["docker-network-proxy.service"];
  };
}
