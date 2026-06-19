_: {
  networking = {
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
      dns = "systemd-resolved";
    };
    useDHCP = false; # NetworkManager handles this
    firewall = {
      enable = true;
      allowPing = false;
      logRefusedConnections = true;
    };
  };

  # DNS over TLS
  services.resolved = {
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
        DNSSEC = "true";
        Domains = ["~."];
        DNSOverTLS = "yes";
      };
    };
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };
  services.blueman.enable = true;
}
