{pkgs, ...}: let
  maildir = "/srv/containers/mrija-archive/maildir";
  data = "/srv/containers/mrija-archive/data";
  envFile = "/srv/containers/mrija-archive/deploy/.env";
in {
  systemd.tmpfiles.rules = [
    "d ${maildir} 0750 vino users -"
    "d ${data} 0750 vino users -"
  ];

  systemd.services.mrija-archive-sync = {
    description = "Trigger mrija-archive daily mail sync";
    after = ["network-online.target" "docker.service"];
    requires = ["docker.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "vino";
      ExecStart = pkgs.writeShellScript "mrija-sync" ''
        set -euo pipefail
        API_KEY=$(grep '^MRIJA_API_KEY=' ${envFile} | cut -d= -f2-)
        ${pkgs.curl}/bin/curl -sf -X POST http://127.0.0.1:8081/api/sync \
          -H "X-API-Key: $API_KEY"
        echo "Sync triggered."
      '';
    };
  };

  systemd.timers.mrija-archive-sync = {
    description = "Periodic mrija.org mail sync";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
    };
  };
}
