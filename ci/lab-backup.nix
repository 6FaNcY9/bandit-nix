# Backup contract (hardening phase 5, decision D7). Evaluates bandit-lab with
# bandit-lab.backups.enable = true so a broken module is caught now, not on the
# day it is switched on. Evaluation-time assertions plus a grep of the prepare
# script; nothing is built or contacted.
{
  pkgs,
  lib,
  labOn,
  labOff,
}: let
  # The Grafana provisioning directory is mounted from the store; take its path
  # from the volume (with string context, so building this check builds it).
  provisioningOf = cfg:
    lib.head (lib.splitString ":" (lib.findFirst (v: lib.hasSuffix ":/etc/grafana/provisioning:ro" v) (throw "no grafana provisioning volume") cfg.virtualisation.quadlet.containers.grafana.containerConfig.volumes));
  b = labOn.services.restic.backups.lab;
  prepare = b.backupPrepareCommand;
  secretNames = lib.filter (n: lib.hasPrefix "restic-" n && !lib.hasPrefix "restic-peer-" n) (lib.attrNames labOn.sops.secrets);
  expectedSecrets = ["restic-password" "restic-repository" "restic-s3-access-key-id" "restic-s3-secret-access-key"];
  mustBackUp = ["/var/backup/postgresql" "/srv/containers/aiia/content-data" "/srv/containers/mrija-archive/maildir"];
in
  assert lib.assertMsg (lib.sort lib.lessThan secretNames == expectedSecrets) "backup secrets must be exactly ${toString expectedSecrets}, found ${toString secretNames}";
  assert lib.assertMsg ((b.repository or null) == null && !(b ? password)) "repository and password must come from sops files, never from inline Nix strings (they would land in the world-readable store)";
  assert lib.assertMsg (lib.hasPrefix "/run/secrets/" b.passwordFile && lib.hasPrefix "/run/secrets/" b.repositoryFile) "password and repository files must be sops-delivered";
  assert lib.assertMsg b.initialize "the repository must be initialised on first run";
  assert lib.assertMsg (lib.all (p: lib.elem p b.paths) mustBackUp) "backup paths must include ${toString mustBackUp}";
  assert lib.assertMsg (lib.any (lib.hasPrefix "--keep-daily") b.pruneOpts && lib.any (lib.hasPrefix "--keep-monthly") b.pruneOpts) "retention must keep daily and monthly snapshots";
  assert lib.assertMsg (lib.hasInfix ".backup" prepare && lib.hasInfix "--single-transaction" prepare) "databases must be snapshotted consistently (sqlite .backup, mysqldump --single-transaction)";
  assert lib.assertMsg (lib.hasInfix "minecraft-snapshot" prepare) "the Minecraft world must be captured through the save-flushing snapshot, never a plain copy";
  # Phase 5.5: the live server is the nix-minecraft one; a snapshot of the stopped Docker container would back up a cold, stale copy.
  assert lib.assertMsg (lib.hasInfix "MC_UNIT=minecraft-server-paper MC_DATA=/srv/minecraft/paper /nix/store/" prepare) "the restic job must snapshot the nix-minecraft server (MC_UNIT/MC_DATA)";
  assert lib.assertMsg (lib.elem "minecraft-server-paper.service" labOn.systemd.services.restic-backups-lab.after && !(lib.elem "docker-minecraft.service" labOn.systemd.services.restic-backups-lab.after)) "the restic job runs after the nix-minecraft server, not the stopped Docker one";
  assert lib.assertMsg (!(lib.hasInfix " -p" prepare)) "no inline database password on a command line";
  assert lib.assertMsg (labOn.systemd.timers ? restic-check && lib.hasInfix "--read-data-subset" labOn.systemd.services.restic-check.script) "the weekly integrity check must exist";
    pkgs.runCommand "lab-backup" {nativeBuildInputs = [pkgs.gnugrep];} ''
      # Missing backup metrics must alert once backups are on, and stay quiet
      # while they are off (the series do not exist yet).
      grep -q 'noDataState: Alerting' ${provisioningOf labOn}/alerting/bandit-lab.yaml
      grep -q 'noDataState: OK' ${provisioningOf labOff}/alerting/bandit-lab.yaml
      ! grep -q 'noDataState: Alerting' ${provisioningOf labOff}/alerting/bandit-lab.yaml
      touch "$out"
    ''
