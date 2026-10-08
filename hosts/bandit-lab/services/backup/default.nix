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
  repoConfig,
  ...
}: let
  cfg = config.bandit-lab.backups;
  staging = "/var/backup/restic-staging";
  shared = import ./shared.nix {inherit pkgs;};
  repositoryFile = config.sops.secrets."restic-repository".path;
  passwordFile = config.sops.secrets."restic-password".path;
  environmentFile = config.sops.templates."restic-b2.env".path;
  resticBin = "${pkgs.restic}/bin/restic";
in {
  imports = [./peer.nix ../../../../nixos/restic-peer-server.nix];

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

    # sqlite3 is needed on the host by the snapshot commands and the restore drill.
    environment.systemPackages = [pkgs.sqlite];

    services.restic.backups.lab = {
      initialize = true;
      inherit repositoryFile passwordFile environmentFile;

      paths = shared.paths staging;
      extraBackupArgs = ["--exclude-caches"];

      # Consistent snapshots: see shared.nix.
      backupPrepareCommand = shared.prepare staging;
      backupCleanupCommand = "find ${staging} -mindepth 1 -delete";

      pruneOpts = repoConfig.backupPeer.retention;
      timerConfig = {
        OnCalendar = "04:30"; # after the 03:15 PostgreSQL dump
        Persistent = true;
        RandomizedDelaySec = "20m";
      };
    };

    systemd = {
      # Staging area for consistent snapshots; root only, emptied after each run.
      tmpfiles.rules = ["d ${staging} 0700 root root -"];

      # A stalled B2 upload or a blocked repository lock would otherwise leave a
      # oneshot "activating" forever: no failed state, no alert, and the timer
      # silently does nothing. Fail instead. Size 12 h against the data volume
      # and upload speed (raise it for the very first run if needed). The
      # databases are dumped from running containers, so start after them.
      services.restic-backups-lab = {
        inherit (shared) after;
        serviceConfig.TimeoutStartSec = "12h";
      };

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
          TimeoutStartSec = "6h";
        };
        script = ''
          export RESTIC_REPOSITORY="$(< ${repositoryFile})"
          export RESTIC_PASSWORD_FILE=${passwordFile}
          export RESTIC_CACHE_DIR=/var/cache/restic-check
          # Wait for a running backup/prune instead of failing with a false alert.
          ${resticBin} --retry-lock 2h check --read-data-subset=5%
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
