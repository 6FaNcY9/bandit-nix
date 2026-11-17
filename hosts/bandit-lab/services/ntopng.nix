# ntopng: live flows per host, port and application (nDPI) on the WAN and
# tailnet interfaces, reachable as the Tailscale Service svc:ntopng
# (tailnet-https.nix). Per-host live capture in the UI yields a pcap for
# Wireshark; tcpdump is on the host for the raw packet view.
# shortcut: community edition keeps flows in memory and RRD only, no full
# packet store; switch to Arkime when every packet must be kept.
{
  config,
  pkgs,
  ...
}: let
  # Keyless geolocation: ntopng reads a City db (country+city) and an ASN db from --geoip-dir.
  # DB-IP lite needs no MaxMind licence key (already in nixpkgs, also used by mrija-watch);
  # its filenames match ntopng's dbip-city / dbip-asn scan.
  geoipDir = pkgs.linkFarm "ntopng-geoip" [
    {
      name = "dbip-city-lite.mmdb";
      path = "${pkgs.dbip-city-lite}/share/dbip/dbip-city-lite.mmdb";
    }
    {
      name = "dbip-asn-lite.mmdb";
      path = "${pkgs.dbip-asn-lite}/share/dbip/dbip-asn-lite.mmdb";
    }
  ];
in {
  services.ntopng = {
    enable = true;
    # configText replaces the module's generated file: its --http-port takes
    # a bare port, which would listen on every interface.
    configText = ''
      --interface=enp44s0
      --interface=tailscale0
      --http-port=127.0.0.1:3003
      --redis=${config.services.ntopng.redis.address}
      --data-dir=/var/lib/ntopng
      --geoip-dir=${geoipDir}
      --user=ntopng
    '';
  };

  environment.systemPackages = [pkgs.tcpdump];
}
