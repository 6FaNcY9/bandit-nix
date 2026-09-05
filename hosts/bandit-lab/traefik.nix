{pkgs, ...}: let
  # Inspect-then-create: a plain `docker network create proxy || true` would
  # also mask real daemon failures (wedged socket, disk full), leaving every
  # dependent container unit to fail later with an obscure "network not
  # found". Matches the pattern in webhost.nix for portainer-control.
  ensureProxyNetwork = pkgs.writeShellScript "ensure-proxy-network" ''
    set -euo pipefail

    if ! ${pkgs.docker}/bin/docker network inspect proxy >/dev/null 2>&1; then
      ${pkgs.docker}/bin/docker network create proxy
    fi
  '';
  # The Docker provider needs discovery, inspection and events, never writes
  # or container file access. Keep the privileged socket in a separate process.
  dockerProxyConfig = pkgs.writeText "traefik-docker-proxy.cfg" ''
    global
      maxconn 32
    defaults
      mode http
      timeout connect 5s
      timeout client 1h
      timeout server 1h
    frontend discovery
      bind /run/traefik-docker-proxy/docker.sock mode 660
      acl read_method method GET HEAD
      acl discovery_path path_reg ^(/v[0-9]+\.[0-9]+)?/(_ping|version|events|containers/json|containers/[a-zA-Z0-9_.-]+/json)$
      http-request deny unless read_method discovery_path
      default_backend docker
    backend docker
      server daemon /var/run/docker.sock
  '';
in {
  users.users.traefik-docker-proxy = {
    isSystemUser = true;
    group = "traefik";
    extraGroups = ["docker"];
  };

  systemd.services = {
    traefik-docker-proxy = {
      description = "Read-only Docker discovery API for Traefik";
      requires = ["docker.service"];
      after = ["docker.service"];
      serviceConfig = {
        ExecStart = "${pkgs.haproxy}/bin/haproxy -W -db -f ${dockerProxyConfig}";
        Restart = "on-failure";
        User = "traefik-docker-proxy";
        Group = "traefik";
        RuntimeDirectory = "traefik-docker-proxy";
        RuntimeDirectoryMode = "0750";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        RestrictAddressFamilies = ["AF_UNIX"];
        CapabilityBoundingSet = "";
      };
    };
    traefik = {
      requires = ["traefik-docker-proxy.service"];
      after = ["traefik-docker-proxy.service"];
    };
    # Docker network containers join to be discovered by Traefik.
    # Add to any compose stack: networks: [proxy]
    # and set external: true on the proxy network.
    docker-network-proxy = {
      description = "Create proxy Docker network for Traefik";
      after = ["docker.service"];
      requires = ["docker.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = ensureProxyNetwork;
      };
    };
  };

  services.traefik = {
    enable = true;
    staticConfigOptions = {
      log.level = "INFO";
      entryPoints.web = {
        address = "127.0.0.1:80";
        forwardedHeaders.trustedIPs = [
          "127.0.0.1/32"
          "::1/128"
        ];
      };
      providers.docker = {
        endpoint = "unix:///run/traefik-docker-proxy/docker.sock";
        exposedByDefault = false;
        network = "proxy";
      };
    };
  };
}
