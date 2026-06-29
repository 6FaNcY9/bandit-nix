{config, ...}: {
  systemd.tmpfiles.rules = [
    "d /srv/containers/vaultwarden 0750 vino users -"
    "d /srv/containers/vaultwarden/data 0750 vino users -"
  ];

  sops.templates."vaultwarden.env" = {
    mode = "0400";
    content = ''
      ADMIN_TOKEN=${config.sops.placeholder."vaultwarden-admin-token"}
      SIGNUPS_ALLOWED=false
      INVITATIONS_ALLOWED=true
      DOMAIN=https://vault.bandit-lab.mrija.org
      IP_HEADER=CF-Connecting-IP
    '';
  };

  virtualisation.oci-containers.containers.vaultwarden = {
    image = "vaultwarden/server@sha256:d626d04934cd1192ad8ced1adb975099fca78cec33ab467d2d3c923cde7f3b0c";
    volumes = ["/srv/containers/vaultwarden/data:/data"];
    environment = {
      WEBSOCKET_ENABLED = "true";
    };
    environmentFiles = [config.sops.templates."vaultwarden.env".path];
    extraOptions = [
      "--network=proxy"
      "--label=traefik.enable=true"
      "--label=traefik.http.routers.vaultwarden.rule=Host(`vault.bandit-lab.mrija.org`)"
      "--label=traefik.http.routers.vaultwarden.entrypoints=web"
      "--label=traefik.http.services.vaultwarden.loadbalancer.server.port=80"
    ];
  };

  systemd.services.docker-vaultwarden = {
    after = ["docker-network-proxy.service"];
    requires = ["docker-network-proxy.service"];
  };
}
