{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  username = repoConfig.workstation.username;
  maildir = "/srv/containers/mrija-archive/maildir";
  data = "/srv/containers/mrija-archive/data";
  envFile = config.sops.templates."mrija-archive.env".path;
in {
  sops = {
    secrets = {
      "mrija-api-key" = {};
      "mrija-password" = {};
    };

    templates."mrija-archive.env" = {
      owner = username;
      group = "users";
      mode = "0400";
      content = ''
        MRIJA_API_KEY=${config.sops.placeholder."mrija-api-key"}
        MRIJA_PASSWORD=${config.sops.placeholder."mrija-password"}
      '';
    };
  };

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
        TimeoutStartSec = "35min";
        ExecStart = pkgs.writeShellScript "mrija-sync" ''
          set -euo pipefail
          : "''${MRIJA_API_KEY:?missing MRIJA_API_KEY in ${envFile}}"

          trigger_response="$(
            ${pkgs.curl}/bin/curl -sf --max-time 30 -X POST \
              http://127.0.0.1:8081/api/sync \
              -H "X-API-Key: ''${MRIJA_API_KEY}"
          )"
          ${pkgs.jq}/bin/jq -e '.status == "started"' \
            <<<"''${trigger_response}" >/dev/null

          progress="$(
            ${pkgs.curl}/bin/curl -sfN --max-time 1800 \
              http://127.0.0.1:8081/api/update/progress \
              -H "X-API-Key: ''${MRIJA_API_KEY}"
          )"
          final_event="$(
            ${pkgs.coreutils}/bin/printf '%s\n' "''${progress}" |
              ${pkgs.gnused}/bin/sed -n 's/^data: //p' |
              ${pkgs.coreutils}/bin/tail -n 1
          )"
          status="$(
            ${pkgs.coreutils}/bin/printf '%s\n' "''${final_event}" |
              ${pkgs.jq}/bin/jq -er '.status | strings'
          )"

          case "''${status}" in
            "Sync complete"*)
              ${pkgs.coreutils}/bin/printf '%s\n' "''${status}"
              ;;
            *)
              ${pkgs.coreutils}/bin/printf \
                'mrija archive sync did not complete: %s\n' \
                "''${status}" >&2
              exit 1
              ;;
          esac
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
