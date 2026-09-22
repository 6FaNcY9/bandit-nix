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
      # No restartUnits: the container is Portainer-managed (not defined in
      # this repo), so after a sops rotation restart the mrija-archive
      # container manually (Portainer UI or `docker restart`). The oneshot
      # sync service re-reads this EnvironmentFile on every run.
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
      "C+ /srv/containers/mrija-archive/deploy/known_hosts 0644 root root - ${./thehost-known_hosts}"
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
        # Sandboxing: the job only curls 127.0.0.1:8081 and needs nothing else.
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
        # Docker DNAT reaches the proxy on its dynamic shared-network address.
        IPAddressAllow = ["localhost" "172.18.0.0/16"];
        IPAddressDeny = ["any"];
        ExecStart = pkgs.writeShellScript "mrija-sync" ''
          set -euo pipefail
          : "''${MRIJA_API_KEY:?missing MRIJA_API_KEY in ${envFile}}"

          phase_start=$SECONDS
          ${pkgs.coreutils}/bin/printf '%s\n' \
            'mrija sync phase=post_trigger event=start' >&2
          trigger_response_file="$(${pkgs.coreutils}/bin/mktemp)"
          trap '${pkgs.coreutils}/bin/rm -f "''${trigger_response_file}"' EXIT
          if trigger_http_status="$(${pkgs.curl}/bin/curl -sS --max-time 30 -X POST \
              http://127.0.0.1:8081/api/sync \
              -H "X-API-Key: ''${MRIJA_API_KEY}" \
              -o "''${trigger_response_file}" -w '%{http_code}')"; then
            :
          else
            curl_status=$?
            ${pkgs.coreutils}/bin/printf \
              'mrija sync phase=post_trigger event=failed rc=%s elapsed=%ss\n' \
              "''${curl_status}" "$((SECONDS - phase_start))" >&2
            exit "''${curl_status}"
          fi
          ${pkgs.coreutils}/bin/printf \
            'mrija sync phase=post_trigger event=complete elapsed=%ss\n' \
            "$((SECONDS - phase_start))" >&2
          case "''${trigger_http_status}" in
            2??)
              if ${pkgs.jq}/bin/jq -e '.status == "started"' \
                "''${trigger_response_file}" >/dev/null; then
                :
              else
                parse_status=$?
                ${pkgs.coreutils}/bin/printf \
                  'mrija sync phase=post_trigger_parse event=failed rc=%s elapsed=%ss\n' \
                  "''${parse_status}" "$((SECONDS - phase_start))" >&2
                exit "''${parse_status}"
              fi
              ;;
            409)
              if ${pkgs.jq}/bin/jq -e \
                '.detail == "Sync already in progress"' \
                "''${trigger_response_file}" >/dev/null; then
                ${pkgs.coreutils}/bin/printf '%s\n' \
                  'mrija sync phase=post_trigger event=already_in_progress action=join_sse' >&2
              else
                parse_status=$?
                ${pkgs.coreutils}/bin/printf \
                  'mrija sync phase=post_trigger_parse event=failed rc=%s elapsed=%ss\n' \
                  "''${parse_status}" "$((SECONDS - phase_start))" >&2
                exit "''${parse_status}"
              fi
              ;;
            *)
              ${pkgs.coreutils}/bin/printf \
                'mrija sync phase=post_trigger event=failed http_status=%s elapsed=%ss\n' \
                "''${trigger_http_status}" "$((SECONDS - phase_start))" >&2
              exit 1
              ;;
          esac

          phase_start=$SECONDS
          ${pkgs.coreutils}/bin/printf '%s\n' \
            'mrija sync phase=sse_progress event=start' >&2
          if progress="$(
            ${pkgs.curl}/bin/curl -sfN --max-time 1800 \
              http://127.0.0.1:8081/api/update/progress \
              -H "X-API-Key: ''${MRIJA_API_KEY}"
          )"; then
            ${pkgs.coreutils}/bin/printf \
              'mrija sync phase=sse_progress event=complete elapsed=%ss\n' \
              "$((SECONDS - phase_start))" >&2
          else
            curl_status=$?
            ${pkgs.coreutils}/bin/printf \
              'mrija sync phase=sse_progress event=failed rc=%s elapsed=%ss\n' \
              "''${curl_status}" "$((SECONDS - phase_start))" >&2
            exit "''${curl_status}"
          fi

          phase_start=$SECONDS
          ${pkgs.coreutils}/bin/printf '%s\n' \
            'mrija sync phase=final_status event=start' >&2
          if final_event="$(
            ${pkgs.coreutils}/bin/printf '%s\n' "''${progress}" |
              ${pkgs.gnused}/bin/sed -n 's/^data: //p' |
              ${pkgs.coreutils}/bin/tail -n 1
          )" && status="$(
            ${pkgs.coreutils}/bin/printf '%s\n' "''${final_event}" |
              ${pkgs.jq}/bin/jq -er '.status | strings'
          )"; then
            ${pkgs.coreutils}/bin/printf \
              'mrija sync phase=final_status event=complete elapsed=%ss\n' \
              "$((SECONDS - phase_start))" >&2
          else
            parse_status=$?
            ${pkgs.coreutils}/bin/printf \
              'mrija sync phase=final_status event=failed rc=%s elapsed=%ss\n' \
              "''${parse_status}" "$((SECONDS - phase_start))" >&2
            exit "''${parse_status}"
          fi

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
      enable = true;
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        Persistent = true;
      };
    };
  };
}
