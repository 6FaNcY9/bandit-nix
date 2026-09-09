{
  config,
  pkgs,
  ...
}: let
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
        # AF_UNIX covers the actual sockets; AF_INET/AF_INET6 are required
        # because HAProxy >= 3.1 probes QUIC socket options at startup and
        # exits fatally when the INET families are blocked. No inet sockets
        # are bound or connected by the config.
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
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

  # Access-log destination shared with the CrowdSec engine (the reader):
  # group crowdsec may traverse the dir; files Traefik creates are 0644.
  systemd.tmpfiles.rules = [
    "d /var/log/traefik 0750 traefik crowdsec - -"
  ];

  # The access log no longer lands in the journal, so rotate it on disk.
  # copytruncate avoids having to signal Traefik to reopen the file.
  services.logrotate.settings."/var/log/traefik/access.log" = {
    frequency = "daily";
    rotate = 14;
    compress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
  };

  services.traefik = {
    enable = true;
    staticConfigOptions = {
      log.level = "INFO";
      # JSON access log to a file instead of stdout: the CrowdSec engine
      # (hosts/bandit-lab/crowdsec.nix) reads it with a file acquisition.
      # Journald is unusable as a transport here — the crowdsec journalctl
      # source reads the default short format, so every line arrives with a
      # "MMM DD HH:MM:SS host traefik[pid]: " prefix that breaks both the
      # CLF and JSON branches of crowdsecurity/traefik-logs.
      accessLog = {
        format = "json";
        filePath = "/var/log/traefik/access.log";
      };
      entryPoints.web = {
        address = "127.0.0.1:80";
        # Enforce CrowdSec decisions on every public router (see the
        # crowdsec-bouncer middleware below).
        http.middlewares = ["crowdsec-bouncer@file"];
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
      # CrowdSec bouncer plugin: blocks IPs the engine has decisions for
      # before they ever reach a backend.
      experimental.plugins.bouncer = {
        moduleName = "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin";
        version = "v1.7.1";
      };
    };
    dynamicConfigOptions.http.middlewares.crowdsec-bouncer.plugin.bouncer = {
      enabled = true;
      # The LAPI is loopback-only (crowdsec.nix). The plugin resolves the
      # key from this sops-owned file itself — it MUST be crowdsecLapiKeyFile,
      # not crowdsecLapiKey: the latter is sent verbatim as X-Api-Key, and
      # putting a path there made every LAPI call 403 (and every request
      # fail-closed), which rolled the first deploy back.
      crowdsecLapiScheme = "http";
      crowdsecLapiHost = "127.0.0.1:8080";
      crowdsecLapiKeyFile = config.sops.secrets.crowdsec-traefik-bouncer-key.path;
      # Immediate peer is always cloudflared on loopback; the real client
      # IP comes from its X-Forwarded-For.
      forwardedHeadersTrustedIPs = [
        "127.0.0.1/32"
        "::1/128"
      ];
    };
  };
}
