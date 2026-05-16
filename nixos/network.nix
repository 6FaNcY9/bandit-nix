_: {
  networking = {
    networkmanager.enable = true;
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
        DNSSEC = "allow-downgrade";
        Domains = ["~."];
        FallbackDNS = [
          "1.1.1.1" # Cloudflare
          "9.9.9.9" # Quad9 — filters malicious domains
        ];
        DNSOverTLS = "opportunistic";
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
