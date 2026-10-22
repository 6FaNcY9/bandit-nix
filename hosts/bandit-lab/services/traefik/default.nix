{config, ...}: {
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
      # (hosts/bandit-lab/services/crowdsec) reads it with a file acquisition.
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
      # CrowdSec bouncer plugin: blocks IPs the engine has decisions for
      # before they ever reach a backend.
      experimental.plugins.bouncer = {
        moduleName = "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin";
        version = "v1.7.1";
      };
    };
    # Podman services (phase 4): one router per service to its loopback port.
    # No container socket is involved; the former Docker provider and its
    # GET-only HAProxy filter are gone with the last Docker-routed service.
    dynamicConfigOptions.http = {
      routers = {
        grafana = {
          rule = "Host(`grafana.bandit-lab.mrija.org`)";
          entryPoints = ["web"];
          service = "grafana";
        };
        mrija-archive = {
          rule = "Host(`mail-archive.bandit-lab.mrija.org`)";
          entryPoints = ["web"];
          service = "mrija-archive";
        };
        aiia = {
          rule = "Host(`aiia.at`) || Host(`www.aiia.at`) || Host(`aiia.bandit-lab.mrija.org`)";
          entryPoints = ["web"];
          service = "aiia";
        };
        vaultwarden = {
          rule = "Host(`vault.atmosphaere.at`) || Host(`vault.bandit-lab.mrija.org`)";
          entryPoints = ["web"];
          service = "vaultwarden";
        };
      };
      services = {
        grafana.loadBalancer.servers = [{url = "http://127.0.0.1:3000";}];
        mrija-archive.loadBalancer.servers = [{url = "http://127.0.0.1:8081";}];
        aiia.loadBalancer.servers = [{url = "http://127.0.0.1:2368";}];
        vaultwarden.loadBalancer.servers = [{url = "http://127.0.0.1:8222";}];
      };
      # CrowdSec bouncer plugin: see the plugin stanza above.
      middlewares.crowdsec-bouncer.plugin.bouncer = {
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
  };
}
