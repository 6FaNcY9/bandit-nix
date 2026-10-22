{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
  # Compiled by Vaultwarden into the vaultwarden.css served to the web vault.
  vaultwardenTemplates = pkgs.writeTextDir "scss/user.vaultwarden.scss.hbs" (
    builtins.readFile ./gruvbox.scss.hbs
  );
in {
  systemd.tmpfiles.rules = [
    "d /srv/containers/vaultwarden 0750 ${username} users -"
    "d /srv/containers/vaultwarden/data 0750 ${username} users -"
  ];

  # Declared here instead of modules/server/sops.nix so the token is only decrypted on
  # bandit-lab — the laptop never uses it and should never hold it.
  sops.secrets."vaultwarden-admin-token" = {
    mode = "0400";
  };

  sops.templates."vaultwarden.env" = {
    mode = "0400";
    # Podman reads this environment file when the container is created.
    restartUnits = ["vaultwarden.service"];
    content = ''
      ADMIN_TOKEN=${config.sops.placeholder."vaultwarden-admin-token"}
      SIGNUPS_ALLOWED=false
      INVITATIONS_ALLOWED=true
      DOMAIN=https://vault.atmosphaere.at
      IP_HEADER=CF-Connecting-IP
    '';
  };

  # Quadlet container (phase 4): hardened by default, running as the data
  # owner on the podman proxy network; Traefik reaches it on loopback.
  virtualisation.quadlet.containers.vaultwarden.containerConfig = {
    image = "docker.io/vaultwarden/server@sha256:d626d04934cd1192ad8ced1adb975099fca78cec33ab467d2d3c923cde7f3b0c";
    # /srv/containers/vaultwarden is owned by vino (1000:100); as non-root the
    # server cannot bind 80, so it listens on 8080 inside the pod namespace.
    user = "1000:100";
    networks = [config.virtualisation.quadlet.networks.proxy.ref];
    publishPorts = ["127.0.0.1:8222:8080"];
    # The unit is active only once the image's health check passes, so the
    # deploy health gate and Traefik never see a half-started vault.
    notify = "healthy";
    volumes = [
      "/srv/containers/vaultwarden/data:/data"
      "${vaultwardenTemplates}:/templates:ro"
    ];
    environments = {
      # Websockets ride the main port since 1.29 (WEBSOCKET_ENABLED is gone).
      TEMPLATES_FOLDER = "/templates";
      ROCKET_PORT = "8080";
    };
    environmentFiles = [config.sops.templates."vaultwarden.env".path];
  };
}
