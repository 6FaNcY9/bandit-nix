{pkgs, ...}: let
  ipt = "${pkgs.iptables}/bin/iptables";
  ip6t = "${pkgs.iptables}/bin/ip6tables";

  enableScript = pkgs.writeShellScript "tor-routing-enable" ''
    set -euo pipefail

    # ── Create nat chain ───────────────────────────────────────────────
    ${ipt} -t nat -N TOR_TRANS 2>/dev/null || ${ipt} -t nat -F TOR_TRANS

    # Skip Tor daemon's own traffic to avoid routing loops
    ${ipt} -t nat -A TOR_TRANS -m owner --uid-owner tor -j RETURN

    # Skip loopback and RFC-1918 subnets
    ${ipt} -t nat -A TOR_TRANS -d 127.0.0.0/8   -j RETURN
    ${ipt} -t nat -A TOR_TRANS -d 192.168.0.0/16 -j RETURN
    ${ipt} -t nat -A TOR_TRANS -d 10.0.0.0/8     -j RETURN
    ${ipt} -t nat -A TOR_TRANS -d 172.16.0.0/12  -j RETURN

    # Redirect DNS (UDP 53) → Tor DNSPort 9053
    ${ipt} -t nat -A TOR_TRANS -p udp --dport 53 -j REDIRECT --to-ports 9053

    # Redirect all TCP → Tor TransPort 9040
    ${ipt} -t nat -A TOR_TRANS -p tcp --syn -j REDIRECT --to-ports 9040

    # Hook chain into OUTPUT (locally originated packets)
    ${ipt} -t nat -A OUTPUT -j TOR_TRANS

    # ── Create filter chain for leak-blocking rules ────────────────────
    ${ipt} -t filter -N TOR_BLOCK 2>/dev/null || ${ipt} -t filter -F TOR_BLOCK

    # Block ICMP outbound (ping leaks real IP — Tor can't carry ICMP)
    ${ipt} -t filter -A TOR_BLOCK -p icmp ! -o lo -j DROP

    # Block all non-loopback UDP (DNS was redirected to loopback:9053 above)
    ${ipt} -t filter -A TOR_BLOCK -p udp ! -o lo -j DROP

    ${ipt} -t filter -A OUTPUT -j TOR_BLOCK

    # Block IPv6 outbound to prevent leaks (Tor is IPv4-only)
    ${ip6t} -A OUTPUT ! -o lo -j DROP 2>/dev/null || true
  '';

  disableScript = pkgs.writeShellScript "tor-routing-disable" ''
    set -euo pipefail
    ${ipt} -t nat    -D OUTPUT -j TOR_TRANS  2>/dev/null || true
    ${ipt} -t nat    -F TOR_TRANS            2>/dev/null || true
    ${ipt} -t nat    -X TOR_TRANS            2>/dev/null || true
    ${ipt} -t filter -D OUTPUT -j TOR_BLOCK  2>/dev/null || true
    ${ipt} -t filter -F TOR_BLOCK            2>/dev/null || true
    ${ipt} -t filter -X TOR_BLOCK            2>/dev/null || true
    ${ip6t} -D OUTPUT ! -o lo -j DROP        2>/dev/null || true
  '';
in {
  # ── Tor daemon ────────────────────────────────────────────────────────────
  services.tor = {
    enable = true;
    client = {
      enable = true;
      socksListenAddress = {
        addr = "127.0.0.1";
        port = 9050;
      };
      transparentProxy.enable = true;
      dns.enable = true;
    };
    settings = {
      ExitNodes = "{de},{at},{ch},{nl},{se},{fi}";
    };
  };

  # ── Toggle service — start enables routing, stop disables it ─────────────
  systemd.services.tor-routing-enable = {
    description = "Transparent Tor routing via iptables";
    after = ["tor.service" "network.target"];
    requires = ["tor.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = enableScript;
      ExecStop = disableScript;
    };
  };

  # ── Polkit: wheel can toggle routing without password prompt ─────────────
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id === "org.freedesktop.systemd1.manage-units" &&
          subject.isInGroup("wheel")) {
        var unit = action.lookup("unit");
        if (unit === "tor-routing-enable.service") {
          return polkit.Result.YES;
        }
      }
    });
  '';

  environment.systemPackages = with pkgs; [
    tor
    torsocks
    networkmanagerapplet # provides nm-connection-editor
  ];
}
