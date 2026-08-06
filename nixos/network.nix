{
  config,
  lib,
  pkgs,
  ...
}: {
  networking = {
    hosts = {
      "192.168.1.6" = ["fire-tv"];
    };

    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
      plugins = [pkgs.networkmanager-openvpn];
      # Random MAC per network, stable per SSID: defeats cross-network
      # tracking without breaking captive portals or per-network DHCP leases.
      # Laptop-only: bandit-lab is headless and has no Wi-Fi use case.
      wifi = lib.mkIf (config.networking.hostName == "bandit") {
        macAddress = "stable";
      };
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
          # Primary servers with DoT hostnames — enforces encrypted DNS upstream.
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
  };
}
