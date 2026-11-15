# Bump reminder and new-member alert for the Bandit Anarchy Discord (tester search, 2026-11).
# Remove this import once the testers are in; the bump reminder already stops at STOP_AT members.
{pkgs, ...}: let
  watch = pkgs.callPackage ./package.nix {};
  unit = mode: {
    description = "Bandit Anarchy Discord: ${mode} reminder over ntfy";
    after = ["ntfy-seed.service" "network-online.target"];
    requires = ["ntfy-seed.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "werbung-watch";
      EnvironmentFile = "/var/lib/mcbots/ntfy/publisher.env";
      Environment = ["NTFY_URL=http://127.0.0.1:2586" "NTFY_TOPIC=mcbots"];
      ExecStart = "${watch}/bin/werbung-watch ${mode}";
    };
  };
in {
  systemd.services = {
    werbung-bump = unit "bump";
    werbung-members = unit "members";
  };

  systemd.timers = {
    # Every two hours in the day; Disboard allows one bump per two hours.
    werbung-bump = {
      wantedBy = ["timers.target"];
      timerConfig.OnCalendar = "*-*-* 08..22/2:00:00";
    };
    werbung-members = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "10min";
      };
    };
  };
}
