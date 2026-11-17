# New-device watcher: ntfy once when a MAC appears on the home LAN uplink for
# the first time (netwatch.sh; test: netwatch.test.sh). DynamicUser + a 2-min
# timer; the known-MAC list lives in the unit's StateDirectory. ntfy env as in
# notify.nix (the host-side publisher token, loopback ntfy).
{pkgs, ...}: let
  netwatch = pkgs.writeShellApplication {
    name = "lab-netwatch";
    runtimeInputs = [pkgs.iproute2 pkgs.jq pkgs.curl pkgs.coreutils pkgs.gnugrep pkgs.gawk];
    text = builtins.readFile ./netwatch.sh;
  };
in {
  systemd.services.lab-netwatch = {
    description = "Alert on a new device in the home network";
    after = ["ntfy-seed.service" "network-online.target"];
    requires = ["ntfy-seed.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "lab-netwatch";
      EnvironmentFile = "/var/lib/mcbots/ntfy/publisher.env";
      Environment = ["NTFY_URL=http://127.0.0.1:2586" "NTFY_TOPIC=mcbots"];
      ExecStart = "${netwatch}/bin/lab-netwatch";
    };
  };
  systemd.timers.lab-netwatch = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
    };
  };
}
