{
  pkgs,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
  maildir = "/srv/containers/mrija-archive/maildir";
  data = "/srv/containers/mrija-archive/data";
  envFile = "/srv/containers/mrija-archive/deploy/.env";
in {
  systemd = {
    tmpfiles.rules = [
      "d /srv/containers/mrija-archive 0750 ${username} users -"
      "d /srv/containers/mrija-archive/deploy 0750 ${username} users -"
      "d ${maildir} 0750 ${username} users -"
      "d ${data} 0750 ${username} users -"
    ];

    services.mrija-archive-sync = {
      description = "Trigger mrija-archive daily mail sync";
      after = ["network-online.target" "docker.service"];
      wants = ["network-online.target"];
      requires = ["docker.service"];
      serviceConfig = {
        Type = "oneshot";
        User = username;
        EnvironmentFile = envFile;
        ExecStart = pkgs.writeShellScript "mrija-sync" ''
          set -euo pipefail
          : "''${MRIJA_API_KEY:?missing MRIJA_API_KEY in ${envFile}}"
          ${pkgs.curl}/bin/curl -sf --max-time 30 -X POST http://127.0.0.1:8081/api/sync \
            -H "X-API-Key: ''${MRIJA_API_KEY}"
          echo "Sync triggered."
        '';
      };
    };

    timers.mrija-archive-sync = {
      description = "Periodic mrija.org mail sync";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        Persistent = true;
      };
    };
  };
}
