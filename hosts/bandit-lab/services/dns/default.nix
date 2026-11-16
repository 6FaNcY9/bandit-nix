# Tailnet DNS with ad blocking (owner request 2026-11-16, docs/runbooks/lab-dns.md).
# Blocky answers on the tailnet address only; tailnet devices get it via the admin
# console's global nameserver. The lab itself keeps systemd-resolved.
{
  lib,
  repoConfig,
  ...
}: let
  tailnetIp = repoConfig.lab.tailscaleIp;
in {
  services.blocky = {
    enable = true;
    settings = {
      ports.dns = "${tailnetIp}:53";
      # No per-query log: it would record every tailnet device's browsing.
      queryLog.type = "none";
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
        clientGroupsBlock.default = ["ads"];
        blockType = "zeroIp";
        # Answer at once and block once the lists are in; a list download never holds up DNS.
        loading = {
          strategy = "fast";
          refreshPeriod = "24h";
        };
      };
    };
  };

  systemd.services.blocky = {
    # The tailnet address exists only once tailscaled is up; retry until it does.
    after = ["tailscaled.service"];
    wants = ["tailscaled.service"];
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = "5s";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [53];
    allowedUDPPorts = [53];
  };
}
