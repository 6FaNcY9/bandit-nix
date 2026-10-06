# Backup contract (hardening phase 5, decision D7). Evaluates bandit-lab with
# bandit-lab.backups.enable = true so a broken module is caught now, not on the
# day it is switched on. Evaluation-time assertions plus a grep of the prepare
# script; nothing is built or contacted.
{
  pkgs,
  lib,
  labOn,
}: let
  b = labOn.services.restic.backups.lab;
  prepare = b.backupPrepareCommand;
  secretNames = lib.filter (n: lib.hasPrefix "restic-" n) (lib.attrNames labOn.sops.secrets);
  expectedSecrets = ["restic-b2-account-id" "restic-b2-account-key" "restic-password" "restic-repository"];
  mustBackUp = ["/var/backup/postgresql" "/srv/containers/aiia/content-data" "/srv/containers/mrija-archive/maildir"];
in
  assert lib.assertMsg (lib.sort lib.lessThan secretNames == expectedSecrets) "backup secrets must be exactly ${toString expectedSecrets}, found ${toString secretNames}";
  assert lib.assertMsg ((b.repository or null) == null && !(b ? password)) "repository and password must come from sops files, never from inline Nix strings (they would land in the world-readable store)";
  assert lib.assertMsg (lib.hasPrefix "/run/secrets/" b.passwordFile && lib.hasPrefix "/run/secrets/" b.repositoryFile) "password and repository files must be sops-delivered";
  assert lib.assertMsg b.initialize "the repository must be initialised on first run";
  assert lib.assertMsg (lib.all (p: lib.elem p b.paths) mustBackUp) "backup paths must include ${toString mustBackUp}";
  assert lib.assertMsg (lib.any (lib.hasPrefix "--keep-daily") b.pruneOpts && lib.any (lib.hasPrefix "--keep-monthly") b.pruneOpts) "retention must keep daily and monthly snapshots";
  assert lib.assertMsg (lib.hasInfix ".backup" prepare && lib.hasInfix "--single-transaction" prepare) "databases must be snapshotted consistently (sqlite .backup, mysqldump --single-transaction)";
  assert lib.assertMsg (!(lib.hasInfix " -p" prepare)) "no inline database password on a command line";
  assert lib.assertMsg (labOn.systemd.timers ? restic-check && lib.hasInfix "--read-data-subset" labOn.systemd.services.restic-check.script) "the weekly integrity check must exist";
    pkgs.writeText "lab-backup" "ok\n"
