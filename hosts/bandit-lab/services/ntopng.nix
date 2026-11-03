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
}: {
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
      --user=ntopng
    '';
  };

  environment.systemPackages = [pkgs.tcpdump];
}
