_: {
  # Collaborative IPS (docs/specs/2026-09-09-security-lab.md, phase 3):
  # the engine parses journald (sshd + the Traefik JSON access log), enriches
  # with community blocklists via the central API, and bans via profiles.
  # fail2ban stays in place until CrowdSec has proven itself.
  #
  # The firewall bouncer is NOT enabled here yet (phase 3b): the NixOS
  # module's registerBouncer unit conflicts with the engine's state dir
  # (DynamicUser StateDirectory creates /var/lib/crowdsec ->
  # /var/lib/private/* owned by a dynamic UID, starving the engine) and its
  # raw cscli needs /etc/crowdsec/config.yaml the module never renders.
  # Instead the bouncer gets registered once imperatively via the wrapped
  # cscli on the host and authenticates with a sops-provided key
  # (services.crowdsec-firewall-bouncer.secrets.apiKeyPath).
  services.crowdsec = {
    enable = true;
    autoUpdateService = true; # daily cscli hub update
    settings = {
      # LAPI for the bouncers; loopback default (127.0.0.1:8080), no firewall.
      general.api.server.enable = true;
      # Explicit LAPI credential path under the writable state dir — left
      # null, the setup script's `cscli machine add` has nowhere to write.
      # capi.credentialsFile stays null on purpose: when set, the module's
      # `cscli machine add` strictly loads the online credentials file
      # BEFORE its own `capi register` step creates it, so first boot always
      # fails. CAPI enrollment happens once imperatively on the host
      # (`sudo cscli capi register`) after the engine is up.
      lapi.credentialsFile = "/var/lib/crowdsec/state/local_api_credentials.yaml";
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
          filters = ["Alert.Remediation == true && Alert.EventsScope == \"Ip\""];
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
        {
          source = "journalctl";
          journalctl_filter = ["_SYSTEMD_UNIT=traefik.service"];
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
}
