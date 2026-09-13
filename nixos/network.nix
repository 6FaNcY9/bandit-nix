{pkgs, ...}: {
  networking = {
    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
      plugins = [pkgs.networkmanager-openvpn];
    };
    useDHCP = false; # NetworkManager handles this
    firewall = {
      enable = true;
      allowPing = false;
      logRefusedConnections = true;
    };
  };

  # Opportunistic DoT/DNSSEC — encrypt+validate when upstream supports it,
  # auto-fallback to cleartext/unsigned on captive portals instead of hard-failing DNS.
  services = {
    resolved = {
      enable = true;
      settings = {
        Resolve = {
          # TLS identities for public resolvers; DNSOverTLS controls fallback.
          DNS = [
            "1.1.1.1#cloudflare-dns.com"
            "9.9.9.9#dns.quad9.net"
          ];
          FallbackDNS = [
            "1.0.0.1#cloudflare-dns.com"
            "149.112.112.112#dns.quad9.net"
          ];
          DNSSEC = "allow-downgrade";
          Domains = ["~."];
          DNSOverTLS = "opportunistic";
        };
      };
    };

    # IP-based NTP fallbacks so timesyncd can sync even when DNS is broken (e.g. after RTC reset from removing battery)
    timesyncd.servers = [
      "162.159.200.1" # Cloudflare
      "162.159.200.123" # Cloudflare
      "216.239.35.0" # Google
      "216.239.35.4" # Google
    ];
  };
}
