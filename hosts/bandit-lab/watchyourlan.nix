{config, ...}: {
  # Network device discovery: ARP-scans the LAN on a timer and keeps a web
  # inventory with online/offline history and new-host notifications.
  # ARP needs L2 access, so the container runs on the host network — but the
  # GUI binds loopback only and is published through Traefik like everything
  # else. WatchYourLAN has no built-in auth; it must stay behind its
  # Cloudflare Access application (docs/runbooks/cloudflare-access.md).
  virtualisation.oci-containers.containers.watchyourlan = {
    image = "aceberg/watchyourlan@sha256:f77532ca7c3c9a4398cb094df7674013a3d7fcf4699386f1e456c24df6fef00e";
    environment = {
      # wlo1 is the active LAN uplink since the location change (Wi-Fi);
      # enp44s0 is unplugged but stays listed so scanning follows the cable
      # when Ethernet returns (arp-scan errors on a dead interface are
      # cosmetic log noise meanwhile).
      IFACES = "wlo1 enp44s0";
      TZ = config.time.timeZone;
      HOST = "127.0.0.1"; # loopback-only GUI; Traefik proxies it
      PORT = "8840";
      # No PROMETHEUS_ENABLE: /metrics would live on the same loopback-only
      # port, so the bridge-networked Prometheus could never scrape it.
    };
    volumes = ["/srv/containers/watchyourlan/data:/data/WatchYourLAN"];
    extraOptions = [
      "--network=host"
      # ARP scanning needs raw packets and interface control, nothing else.
      "--cap-drop=ALL"
      "--cap-add=NET_RAW"
      "--cap-add=NET_ADMIN"
    ];
  };

  # Host-network containers have no IP on the proxy network, so Traefik's
  # docker provider cannot route to them by label. Route via the file
  # provider to the loopback GUI instead.
  services.traefik.dynamicConfigOptions.http = {
    routers.watchyourlan = {
      rule = "Host(`devices.bandit-lab.mrija.org`)";
      entryPoints = ["web"];
      service = "watchyourlan";
    };
    services.watchyourlan.loadBalancer.servers = [{url = "http://127.0.0.1:8840";}];
  };
}
