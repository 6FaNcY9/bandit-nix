# mrija-watch: a daily protection watch for mrija.org. Two timers (04:00
# collect + instant pushes, 07:00 digest), run as vino with the same sandbox
# as mrija-archive-sync, reusing the archive SSH key by LoadCredential. The
# analysis (mrija_watch.py) only ever emits privacy-safe counts, country codes,
# rule names and web paths - never a mail subject, body, filename or address.
{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  inherit (repoConfig.workstation) username;
  stateDir = "/var/lib/mrija-watch";
  ntfyEnv = "/var/lib/mcbots/ntfy/publisher.env";
  watcher = pkgs.callPackage ./package.nix {};

  # The archive key is deployed to disk by the mrija-archive module's sops
  # secret; reuse it, no new key and no sops change.
  keySecret = config.sops.secrets."thehost-sshkey".path;

  commonEnvironment = {
    STATE_DIR = stateDir;
    NTFY_URL = "http://127.0.0.1:2586";
    NTFY_TOPIC = "mrija";
    MRIJA_MAILDIR = "/srv/containers/mrija-archive/maildir";
    MRIJA_REMOTE = "mrija_org@s16.thehost.com.ua:www/mrija.org/";
    MRIJA_DNS_NAME = "mrija.org";
    MRIJA_HTTP_URL = "https://mrija.org";
    MRIJA_KNOWN_HOSTS = toString ../mrija-archive/thehost-known_hosts;
    MRIJA_KEY = "%d/thehost";
  };

  # Mirrors mrija-archive-sync, but this job must reach the internet (rsync to
  # TheHost, dig to 1.1.1.1, HTTPS to mrija.org), so the archive's localhost-only
  # IPAddress rules are relaxed to allow outbound traffic.
  sandbox = {
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
  };
in {
  systemd.services = {
    mrija-watch-collect = {
      description = "Collect mrija.org mail/web/dns findings and push alerts";
      after = ["network-online.target" "mrija-archive-sync.service"];
      wants = ["network-online.target"];
      onFailure = ["mrija-watch-crash.service"];
      environment = commonEnvironment;
      serviceConfig =
        sandbox
        // {
          Type = "oneshot";
          User = username;
          StateDirectory = "mrija-watch";
          StateDirectoryMode = "0700";
          EnvironmentFile = ntfyEnv;
          LoadCredential = ["thehost:${keySecret}"];
          TimeoutStartSec = "20min";
          ExecStart = "${watcher}/bin/mrija-watch collect";
        };
    };

    mrija-watch-digest = {
      description = "Send the mrija.org daily German digest to the phone";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      onFailure = ["mrija-watch-crash.service"];
      environment = commonEnvironment;
      serviceConfig =
        sandbox
        // {
          Type = "oneshot";
          User = username;
          StateDirectory = "mrija-watch";
          StateDirectoryMode = "0700";
          EnvironmentFile = ntfyEnv;
          TimeoutStartSec = "5min";
          ExecStart = "${watcher}/bin/mrija-watch digest";
        };
    };

    # Only a crash (non-zero exit) reaches here; soft collector errors go into
    # the digest instead. OnFailure is set here, never in notify.nix.
    mrija-watch-crash = {
      description = "Notify that the mrija.org watcher crashed";
      environment = {
        NTFY_URL = "http://127.0.0.1:2586";
        NTFY_TOPIC = "mrija";
      };
      serviceConfig =
        sandbox
        // {
          Type = "oneshot";
          User = username;
          EnvironmentFile = ntfyEnv;
          ExecStart = pkgs.writeShellScript "mrija-watch-crash" ''
            ${pkgs.curl}/bin/curl -fsS \
              -H "Authorization: Bearer ''${NTFY_TOKEN:-}" \
              -H "Title: Mrija: watcher crashed" \
              -H "Priority: high" \
              --data-raw "Mrija: watcher crashed, bitte Logs prüfen" \
              "''${NTFY_URL}/''${NTFY_TOPIC}" || true
          '';
        };
    };
  };

  systemd.timers = {
    mrija-watch-collect = {
      description = "Daily mrija.org collect (after the 03:00 mail sync)";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
      };
    };
    mrija-watch-digest = {
      description = "Daily mrija.org digest to the phone";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 07:00:00";
        Persistent = true;
      };
    };
  };
}
