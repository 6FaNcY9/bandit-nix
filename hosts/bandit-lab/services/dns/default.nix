# Tailnet DNS with ad blocking (owner request 2026-11-16, docs/runbooks/lab-dns.md).
# Blocky answers on the tailnet address only; tailnet devices get it via the admin
# console's global nameserver. The lab itself keeps systemd-resolved.
{
  lib,
  config,
  repoConfig,
  ...
}: let
  tailnetIp = repoConfig.lab.tailscaleIp;
in {
  services.blocky = {
    enable = true;
    settings = {
      ports.dns = "${tailnetIp}:53";
      # Metrics and API on the tailnet address (already required for DNS, unlike the pod gateway,
      # which exists only once a container joins the proxy network). The firewall opens port 4000
      # to the proxy network only (Prometheus job blocky), not to tailscale0.
      ports.http = "${tailnetIp}:4000";
      prometheus.enable = true;
      # Device names for the query log (spec netz-panel decision 5): MagicDNS answers reverse
      # lookups for tailnet IPs. If it is unreachable, queries are still answered, just unnamed.
      clientLookup = {
        upstream = "100.100.100.100";
        singleNameOrder = [1];
      };
      # Query log kept 7 days only (owner request 2026-11-16, spec netz-panel decision 2): it records
      # every tailnet device's browsing, so it is short-lived, reachable over the Unix socket only,
      # and read-only for Grafana (blocky-db-grants below).
      queryLog = {
        type = "postgresql";
        target = "postgres://blocky@/blocky?host=/run/postgresql&sslmode=disable";
        logRetentionDays = 7;
      };
      upstreams = {
        # parallel_best: each query goes to two upstreams, picked by their recent speed
        # and errors, and the first good answer wins.
        strategy = "parallel_best";
        # Encrypted, by IP: no bootstrap lookup needed, and the certificates cover the IPs.
        groups.default = [
          "https://1.1.1.1/dns-query"
          "https://9.9.9.9/dns-query"
          "https://8.8.8.8/dns-query"
        ];
        # Start even if the upstreams are briefly unreachable at boot.
        init.strategy = "fast";
      };
      caching = {
        # Popular names are refreshed before they expire, so they stay cache hits.
        prefetching = true;
        prefetchThreshold = 5;
        maxItemsCount = 100000;
      };
      blocking = {
        denylists.ads = [
          "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
          "https://big.oisd.nl/domainswild2"
        ];
        # Threat-intelligence feed: known malware, phishing and C2 domains (hagezi tif medium,
        # checked 2026-11-16: HTTP 200, ~353k domains).
        denylists.malware = ["https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/tif.medium-onlydomains.txt"];
        clientGroupsBlock.default = ["ads" "malware"];
        blockType = "zeroIp";
        # Answer at once and block once the lists are in; a list download never holds up DNS.
        loading = {
          strategy = "fast";
          refreshPeriod = "24h";
        };
      };
    };
  };

  # Postgres itself is enabled in services/webhost. Peer auth maps the host user to the role of the
  # same name; the host user grafana (uid 472, services/monitoring) matches the Grafana container.
  services.postgresql = {
    ensureDatabases = ["blocky"];
    ensureUsers = [
      {
        name = "blocky";
        ensureDBOwnership = true;
      }
      {name = "grafana";}
    ];
  };

  # Read-only access for Grafana to the tables Blocky creates (now and later).
  systemd.services.blocky-db-grants = {
    wantedBy = ["multi-user.target"];
    after = ["postgresql-setup.service"];
    requires = ["postgresql-setup.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };
    script = ''
      psql=${config.services.postgresql.package}/bin/psql
      $psql -v ON_ERROR_STOP=1 -d postgres -c 'GRANT CONNECT ON DATABASE blocky TO grafana'
      $psql -v ON_ERROR_STOP=1 -d blocky <<'SQL'
      GRANT USAGE ON SCHEMA public TO grafana;
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana;
      ALTER DEFAULT PRIVILEGES FOR ROLE blocky IN SCHEMA public GRANT SELECT ON TABLES TO grafana;
      SQL
    '';
  };

  systemd.services.blocky = {
    # The tailnet address exists only once tailscaled is up; retry until it does.
    # Postgres is ordered before Blocky but not required: DNS must answer without it.
    after = ["tailscaled.service" "postgresql.service" "postgresql-setup.service"];
    wants = ["tailscaled.service" "postgresql.service" "postgresql-setup.service"];
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = "5s";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };

  # The monitoring pod scrapes metrics via the tailnet address (pattern: Velocity rule in notify.nix).
  # shortcut: every container on the proxy network can reach Blocky's API (pause blocking) on the tailnet address; pin to the monitoring pod's IP if a container there is ever untrusted.
  networking.firewall.extraCommands = "iptables -A nixos-fw -s 10.89.0.0/24 -d ${tailnetIp} -p tcp --dport 4000 -j nixos-fw-accept";
  networking.firewall.extraStopCommands = "iptables -D nixos-fw -s 10.89.0.0/24 -d ${tailnetIp} -p tcp --dport 4000 -j nixos-fw-accept || true";

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [53];
    allowedUDPPorts = [53];
  };
}
