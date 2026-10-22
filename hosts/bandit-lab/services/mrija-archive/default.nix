{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  inherit (repoConfig.workstation) homeDirectory username;
  maildir = "/srv/containers/mrija-archive/maildir";
  data = "/srv/containers/mrija-archive/data";
  envFile = config.sops.templates."mrija-archive.env".path;
in {
  sops = {
    secrets = {
      "mrija-api-key" = {};
      "mrija-password" = {};
      # The archive container bind-mounts this SSH identity for the TheHost
      # sync. The lab holds its own copy in secrets/lab.yaml (separate from
      # the laptop's).
      "thehost-sshkey" = {
        owner = username;
        path = "${homeDirectory}/.ssh/thehost_mrija";
        mode = "0600";
      };
    };

    templates."mrija-archive.env" = {
      owner = username;
      group = "users";
      mode = "0400";
      # No restartUnits: the container is host-managed Compose (not defined in
      # this repo), so after a sops rotation restart the mrija-archive
      # container manually (`docker restart`).
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
      after = ["network-online.target" "mrija-archive.service"];
      wants = ["network-online.target"];
      requires = ["mrija-archive.service"];
      serviceConfig = {
        Type = "oneshot";
        User = username;
        EnvironmentFile = envFile;
        LoadCredential = [
          "mrija-api-key:${config.sops.secrets."mrija-api-key".path}"
        ];
        UnsetEnvironment = ["MRIJA_API_KEY" "MRIJA_PASSWORD"];
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
        # The loopback port is DNATed to the container, and the filter sees the
        # translated destination: allow the podman proxy subnet.
        IPAddressAllow = ["localhost" "10.89.0.0/24"];
        IPAddressDeny = ["any"];
        ExecStart = pkgs.writeShellScript "mrija-sync" ''
          set -euo pipefail

          phase_start=$SECONDS
          ${pkgs.coreutils}/bin/printf '%s\n' \
            'mrija sync phase=post_trigger event=start' >&2
          trigger_response_file="$(${pkgs.coreutils}/bin/mktemp)"
          api_header_file="$(${pkgs.coreutils}/bin/mktemp)"
          ${pkgs.coreutils}/bin/chmod 600 "''${api_header_file}"
          credential_file="''${CREDENTIALS_DIRECTORY}/mrija-api-key"
          if [ ! -s "''${credential_file}" ]; then
            ${pkgs.coreutils}/bin/printf '%s\n' \
              'mrija sync failed: missing or empty mrija-api-key credential' >&2
            exit 1
          fi
          api_key="$(${pkgs.coreutils}/bin/cat "''${credential_file}")"
          if [ -z "''${api_key}" ]; then
            ${pkgs.coreutils}/bin/printf '%s\n' \
              'mrija sync failed: missing or empty mrija-api-key credential' >&2
            exit 1
          fi
          ${pkgs.coreutils}/bin/printf 'X-API-Key: %s\n' \
            "''${api_key}" >"''${api_header_file}"
          trap '${pkgs.coreutils}/bin/rm -f "''${trigger_response_file}" "''${api_header_file}"' EXIT
          if trigger_http_status="$(printf '%s\n' \
              'silent' \
              'show-error' \
              'max-time = 30' \
              'request = POST' \
              'url = http://127.0.0.1:8081/api/sync' \
              "output = ''${trigger_response_file}" \
              'write-out = %{http_code}' |
              ${pkgs.curl}/bin/curl --config - -H @"''${api_header_file}")"; then
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
          if progress="$(printf '%s\n' \
              'silent' \
              'show-error' \
              'fail' \
              'no-buffer' \
              'max-time = 1800' \
              'url = http://127.0.0.1:8081/api/update/progress' |
              ${pkgs.curl}/bin/curl --config - -H @"''${api_header_file}"
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

  # The archive as a quadlet container (phase 4): same image (loaded into
  # Podman by hand, see the runbook), same mounts and loopback port, running
  # as the data owner on the podman proxy network.
  virtualisation.quadlet.containers.mrija-archive = {
    containerConfig = {
      image = "localhost/mrija-archive:latest";
      pull = "never";
      # /srv/containers/mrija-archive is owned by vino (1000:100); the uid is not declared in Nix.
      user = "1000:100";
      networks = [config.virtualisation.quadlet.networks.proxy.ref];
      publishPorts = ["127.0.0.1:8081:8080"];
      environmentFiles = [envFile];
      environments = {
        MRIJA_SYNC_REMOTE = "mrija_org@s16.thehost.com.ua";
        MRIJA_SYNC_REMOTE_PATH = "email/mrija.org/";
        MRIJA_SSH_KEY = "/run/secrets/thehost_sshkey";
        MRIJA_MAILDIR = "/maildir";
        MRIJA_DB = "/data/mail_index.sqlite";
        MRIJA_AUDIT_LOG = "/data/audit/events.jsonl";
      };
      volumes = [
        "${data}:/data"
        "${maildir}:/maildir"
        "${config.sops.secrets."thehost-sshkey".path}:/run/secrets/thehost_sshkey:ro"
        "/srv/containers/mrija-archive/deploy/known_hosts:/run/ssh/known_hosts:ro"
      ];
    };
    serviceConfig.ExecCondition = "${pkgs.coreutils}/bin/test -r ${envFile}";
  };
}
