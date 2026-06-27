{...}: {
  systemd.tmpfiles.rules = [
    "d /srv/containers/jellyfin/config 0750 vino users -"
    "d /srv/containers/jellyfin/cache 0750 vino users -"
    "d /srv/storage/media 0770 vino users -"
  ];

  virtualisation.oci-containers.containers.jellyfin = {
    image = "jellyfin/jellyfin:latest";
    volumes = [
      "/srv/containers/jellyfin/config:/config"
      "/srv/containers/jellyfin/cache:/cache"
      "/srv/storage/media:/media:ro"
    ];
    extraOptions = [
      "--network=proxy"
      "--label=traefik.enable=true"
      "--label=traefik.http.routers.jellyfin.rule=Host(`media.bandit-lab.mrija.org`)"
      "--label=traefik.http.routers.jellyfin.entrypoints=web"
      "--label=traefik.http.services.jellyfin.loadbalancer.server.port=8096"
    ];
  };
}
