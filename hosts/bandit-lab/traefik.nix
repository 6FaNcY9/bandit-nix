{pkgs, ...}: {
  # Docker network containers join to be discovered by Traefik.
  # Add to any compose stack: networks: [proxy]
  # and set external: true on the proxy network.
  systemd.services.docker-network-proxy = {
    description = "Create proxy Docker network for Traefik";
    after = ["docker.service"];
    requires = ["docker.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker network create proxy || true'";
    };
  };

  services.traefik = {
    enable = true;
    group = "docker";
    staticConfigOptions = {
      log.level = "INFO";
      entryPoints.web.address = ":80";
      providers.docker = {
        endpoint = "unix:///var/run/docker.sock";
        exposedByDefault = false;
        network = "proxy";
      };
      api = {
        dashboard = true;
        insecure = true;
      };
    };
  };
}
