# Off-host backups for bandit-lab (hardening phase 5, decision D7: Backblaze B2).
# Disabled until the four sops secrets below exist in secrets/lab.yaml; enabling
# without them fails activation, so the switch is one line:
#   bandit-lab.backups.enable = true;
# Steps, restore procedure and the tested-restore checklist:
# docs/runbooks/backup-restore.md. ci/lab-backup.nix evaluates the enabled
# configuration so a broken module cannot wait for the day it is switched on.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.bandit-lab.backups;
  staging = "/var/backup/restic-staging";
  docker = "${pkgs.docker}/bin/docker";
  sqlite = "${pkgs.sqlite}/bin/sqlite3";
  rsync = "${pkgs.rsync}/bin/rsync";
  repositoryFile = config.sops.secrets."restic-repository".path;
  passwordFile = config.sops.secrets."restic-password".path;
  environmentFile = config.sops.templates."restic-b2.env".path;
  resticBin = "${pkgs.restic}/bin/restic";
in {
  options.bandit-lab.backups.enable = lib.mkEnableOption "encrypted off-host restic backups to Backblaze B2";

  config = lib.mkIf cfg.enable {
    sops = {
      secrets = {
        # B2 bucket as a restic repository string, e.g. b2:<bucket>:/
        "restic-repository" = {};
        # Passphrase that encrypts the repository. Losing it loses every backup:
        # keep an offline copy (docs/runbooks/backup-restore.md).
        "restic-password" = {};
        # B2 application key restricted to the one bucket: keyID and key.
        "restic-b2-account-id" = {};
        "restic-b2-account-key" = {};
      };
      templates."restic-b2.env".content = ''
        B2_ACCOUNT_ID=${config.sops.placeholder."restic-b2-account-id"}
        B2_ACCOUNT_KEY=${config.sops.placeholder."restic-b2-account-key"}
      '';
    };

    services.restic.backups.lab = {
      initialize = true;
      inherit repositoryFile passwordFile environmentFile;

      paths = [
        staging
        # Existing local dumps from services.postgresqlBackup (03:15).
        "/var/backup/postgresql"
        # Ghost content (uploads); the database is dumped into the staging area.
        "/srv/containers/aiia/content-images"
        "/srv/containers/aiia/content-media"
        "/srv/containers/aiia/content-files"
        "/srv/containers/aiia/content-data"
        # Mrija archive mail; the SQLite index is snapshotted into staging.
        "/srv/containers/mrija-archive/maildir"
      ];
      extraBackupArgs = ["--exclude-caches"];

      # Consistent snapshots, taken just before restic reads the staging area.
      # Failing here fails the whole run (and alerts) instead of backing up a
      # torn copy. No secret appears on a command line: mysqldump reads the root
      # password from the container's own environment.
      backupPrepareCommand = ''
        set -euo pipefail
        find ${staging} -mindepth 1 -delete
        install -d -m 0700 ${staging}/vaultwarden ${staging}/mrija ${staging}/aiia

        # Vaultwarden: everything except the live SQLite files, then an online
        # SQLite snapshot (safe while the container runs).
        ${rsync} -a --exclude 'db.sqlite3*' --exclude 'icon_cache' \
          /srv/containers/vaultwarden/data/ ${staging}/vaultwarden/
        ${sqlite} /srv/containers/vaultwarden/data/db.sqlite3 \
          ".backup '${staging}/vaultwarden/db.sqlite3'"

        # Mrija archive SQLite index.
        if [ -e /srv/containers/mrija-archive/data/mail_index.sqlite ]; then
          ${sqlite} /srv/containers/mrija-archive/data/mail_index.sqlite \
            ".backup '${staging}/mrija/mail_index.sqlite'"
        fi

        # AiiA / Ghost MySQL: single-transaction dump of every database.
        ${docker} exec aiia-mysql sh -c \
          'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump --single-transaction --routines --events --all-databases -uroot' \
          | ${pkgs.gzip}/bin/gzip -c > ${staging}/aiia/mysql.sql.gz
      '';
      backupCleanupCommand = "find ${staging} -mindepth 1 -delete";

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 2"
      ];
      timerConfig = {
        OnCalendar = "04:30"; # after the 03:15 PostgreSQL dump
        Persistent = true;
        RandomizedDelaySec = "20m";
      };
    };

    systemd = {
      # Staging area for consistent snapshots; root only, emptied after each run.
      tmpfiles.rules = ["d ${staging} 0700 root root -"];

      # Integrity check: repository structure plus a rotating 5% sample of the
      # actual data every week (a full read-everything check would download the
      # whole repository from B2).
      services.restic-check = {
        description = "Verify the restic repository";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = environmentFile;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          CacheDirectory = "restic-check";
        };
        script = ''
          export RESTIC_REPOSITORY="$(< ${repositoryFile})"
          export RESTIC_PASSWORD_FILE=${passwordFile}
          export RESTIC_CACHE_DIR=/var/cache/restic-check
          ${resticBin} check --read-data-subset=5%
        '';
      };
      timers.restic-check = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "Sun 06:00";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };
    };
  };
}
