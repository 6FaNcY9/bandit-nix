_: {
  networking = {
    networkmanager = {
      enable = true;
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
          DNSSEC = "true";
          Domains = ["~."];
          DNSOverTLS = "yes";
        };
      };
    };

    # Gnome Keyring - needed for nm-applet to prompt for wifi passwords
    gnome.gnome-keyring.enable = true;

    blueman.enable = true;
  };
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };
}
