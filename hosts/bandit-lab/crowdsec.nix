{config, ...}: {
  # Collaborative IPS (docs/specs/2026-09-09-security-lab.md, phase 3):
  # the engine parses journald (sshd + the Traefik JSON access log), enriches
  # with community blocklists via the central API, and bans via profiles.
  # fail2ban stays in place until CrowdSec has proven itself.
  #
  # The bouncers are registered once imperatively via the wrapped cscli on
  # the host (`cscli bouncers add <name>`) and authenticate with sops keys:
  # the NixOS module's registerBouncer unit is unusable — its DynamicUser
  # StateDirectory creates /var/lib/crowdsec -> /var/lib/private/* owned by
  # a dynamic UID (starving the engine's state dir), and its raw cscli
  # needs /etc/crowdsec/config.yaml the module never renders.
  sops.secrets = {
    crowdsec-firewall-bouncer-key = {};
    # Read by the Traefik process (the plugin's crowdsecLapiKeyFile option),
    # so it must be owned by the traefik user.
    crowdsec-traefik-bouncer-key.owner = "traefik";
  };
  services.crowdsec = {
    enable = true;
    autoUpdateService = true; # daily cscli hub update
    settings = {
      # LAPI for the bouncers; loopback default (127.0.0.1:8080), no firewall.
      general.api.server.enable = true;
      # Explicit credential paths under the writable state dir.
      # Bootstrap caveat: the module's setup script runs `cscli machine add`
      # BEFORE `cscli capi register`, and machine add strictly loads the
      # online credentials file when capi.credentialsFile is set — so on
      # first boot this option must stay null. The file below was enrolled
      # once imperatively (`sudo cscli capi register -f <path>`); only then
      # could the option be enabled. If the state dir is ever wiped, repeat
      # that dance: deploy with the line commented out, register, re-enable.
      lapi.credentialsFile = "/var/lib/crowdsec/state/local_api_credentials.yaml";
      capi.credentialsFile = "/var/lib/crowdsec/state/online_api_credentials.yaml";
    };
    hub.collections = [
      "crowdsecurity/linux"
      "crowdsecurity/sshd"
      "crowdsecurity/traefik"
      "crowdsecurity/http-cve"
    ];
    localConfig = {
      # Without profiles the engine alerts but never decides (module warns).
      profiles = [
        {
          name = "default_ip_remediation";
          filters = ["Alert.Remediation == true && Alert.GetScope() == \"Ip\""];
          decisions = [
            {
              type = "ban";
              duration = "4h";
            }
          ];
          on_success = "break";
        }
      ];
      acquisitions = [
        {
          source = "journalctl";
          journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
          labels.type = "syslog";
        }
        # Traefik's JSON access log from a file, not journald: the journalctl
        # source passes the default short format (with a syslog-style prefix)
        # that crowdsecurity/traefik-logs cannot parse. See traefik.nix.
        {
          source = "file";
          filenames = ["/var/log/traefik/access.log"];
          labels.type = "traefik";
        }
      ];
      # Never raise alerts on traffic that physically cannot be hostile:
      # LAN, tailnet, and the private ranges containers live in. Public HTTP
      # is unaffected — Traefik logs the real client IP from Cloudflare's XFF.
      parsers.s02Enrich = [
        {
          name = "bandit-lab/private-ranges";
          description = "Whitelist LAN, tailnet and private container ranges";
          whitelist = {
            reason = "trusted private ranges";
            ip = ["127.0.0.1" "::1"];
            cidr = ["192.168.0.0/24" "100.64.0.0/10" "10.0.0.0/8" "172.16.0.0/12"];
          };
        }
      ];
    };
  };

  # Enforce engine decisions in the host firewall. The bouncer polls the
  # loopback LAPI and maintains a DROP ipset (lab firewall is iptables;
  # the module picks the mode from networking.nftables.enable). The key
  # comes from sops, never the store.
  services.crowdsec-firewall-bouncer = {
    enable = true;
    # Registered imperatively on the host; the module's registerBouncer
    # unit is unusable on NixOS (see the header comment).
    registerBouncer.enable = false;
    secrets.apiKeyPath = config.sops.secrets.crowdsec-firewall-bouncer-key.path;
    # INPUT alone leaves published container ports untouched; DOCKER-USER is
    # where Docker lets administrators filter forwarded traffic, so the CAPI
    # blocklist drops hostile IPs before they reach any published port too.
    settings.iptables_chains = [
      "INPUT"
      "DOCKER-USER"
    ];
  };
}
