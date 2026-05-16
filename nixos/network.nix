{ ... }:
{
  networking = {
    networkmanager.enable = true;
    useDHCP = false;            # NetworkManager handles this
    firewall = {
      enable = true;
      allowPing = false;
      logRefusedConnections = true;
    };
  };

  # DNS over TLS
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    domains = [ "~." ];
    fallbackDns = [
      "1.1.1.1"   # Cloudflare
      "9.9.9.9"   # Quad9 — filters malicious domains
    ];
    settings = {
      Resolve.DNSOverTLS = "opportunistic";
    };
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };
  services.blueman.enable = true;
}
