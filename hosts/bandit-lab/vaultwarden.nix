{pkgs, ...}: {
  systemd.tmpfiles.rules = [
    "d /srv/containers/vaultwarden 0750 vino users -"
    "d /srv/containers/vaultwarden/data 0750 vino users -"
  ];

  system.activationScripts.ensureVaultwardenEnv = ''
    env_file=/srv/containers/vaultwarden/env
    if [ ! -e "$env_file" ]; then
      token=$(
        ${pkgs.coreutils}/bin/tr -dc A-Za-z0-9 </dev/urandom |
          ${pkgs.coreutils}/bin/head -c 48
      )
      {
        echo "ADMIN_TOKEN=$token"
        echo "SIGNUPS_ALLOWED=false"
        echo "INVITATIONS_ALLOWED=true"
        echo "DOMAIN=https://vault.bandit-lab.mrija.org"
      } > "$env_file"
      ${pkgs.coreutils}/bin/chown vino:users "$env_file"
      ${pkgs.coreutils}/bin/chmod 0600 "$env_file"
    fi
  '';

  virtualisation.oci-containers.containers.vaultwarden = {
    image = "vaultwarden/server@sha256:d626d04934cd1192ad8ced1adb975099fca78cec33ab467d2d3c923cde7f3b0c";
    volumes = ["/srv/containers/vaultwarden/data:/data"];
    environment = {
      WEBSOCKET_ENABLED = "true";
    };
    environmentFiles = ["/srv/containers/vaultwarden/env"];
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
