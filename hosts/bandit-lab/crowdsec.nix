_: {
  # Collaborative IPS (docs/specs/2026-09-09-security-lab.md, phase 3):
  # the engine parses journald (sshd + the Traefik JSON access log), enriches
  # with community blocklists via the central API, and the firewall bouncer
  # enforces decisions in its own nftables table. fail2ban stays in place
  # until CrowdSec has proven itself — do not remove one for the other.
  #
  # Scope note: firewall bans only affect direct-hit traffic (sshd, Samba).
  # All public HTTP arrives through the Cloudflare tunnel and never touches
  # the host firewall — that path gets its own enforcement via the Traefik
  # bouncer plugin (phase 3b, needs a cscli-registered bouncer key in sops).
  services.crowdsec = {
    enable = true;
    autoUpdateService = true; # daily cscli hub update
    # LAPI keeps its loopback default (127.0.0.1:8080): only the local
    # bouncers consume it, so openFirewall stays false.
    hub.collections = [
      "crowdsecurity/linux"
      "crowdsecurity/sshd"
      "crowdsecurity/traefik"
      "crowdsecurity/http-cve"
    ];
    localConfig = {
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

  services.crowdsec-firewall-bouncer = {
    enable = true;
    # registerBouncer keeps its default (auto-register to the local LAPI —
    # the module manages the API key, no manual cscli step). The bouncer
    # enforces in its own nftables table, leaving the NixOS firewall
    # (inet nixos-fw) untouched.
  };
}
