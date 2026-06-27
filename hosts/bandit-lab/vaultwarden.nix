{...}: {
  systemd.tmpfiles.rules = [
    "d /srv/containers/vaultwarden/data 0750 vino users -"
  ];

  virtualisation.oci-containers.containers.vaultwarden = {
    image = "vaultwarden/server:latest";
    volumes = ["/srv/containers/vaultwarden/data:/data"];
    environment = {
      DOMAIN = "https://vault.bandit-lab.mrija.org";
      SIGNUPS_ALLOWED = "false";
      INVITATIONS_ALLOWED = "true";
      WEBSOCKET_ENABLED = "true";
    };
    environmentFiles = ["/srv/containers/vaultwarden/.env"];
    extraOptions = [
      "--network=proxy"
      "--label=traefik.enable=true"
      "--label=traefik.http.routers.vaultwarden.rule=Host(`vault.bandit-lab.mrija.org`)"
      "--label=traefik.http.routers.vaultwarden.entrypoints=web"
      "--label=traefik.http.services.vaultwarden.loadbalancer.server.port=80"
    ];
  };
}
