# Usage numbers for the Grafana "aiia" dashboard (stats.sh, test: stats.test.sh):
# aggregate counts from the pod's Redis as node-exporter textfile metrics.
# Root, because the rootful pod's Redis is only reachable with podman exec;
# no new port, nothing published.
{pkgs, ...}: {
  systemd.services.aiia-create-stats = {
    description = "Collect aiia-create usage counts for Grafana";
    after = ["aiia-create-redis.service"];
    path = [pkgs.podman pkgs.coreutils pkgs.curl pkgs.gawk pkgs.gnugrep pkgs.gnused];
    environment.AIIA_TEXTFILE_DIR = "/var/lib/node-exporter-textfile";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "aiia-create-stats" (builtins.readFile ./stats.sh);
      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectSystem = "full";
    };
  };
  systemd.timers.aiia-create-stats = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "5min";
    };
  };
}
