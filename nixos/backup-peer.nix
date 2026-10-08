# Peer backups, laptop side (docs/runbooks/backup-peer.md): important personal
# data goes to the restic REST server on bandit-lab, and the laptop hosts the
# lab's backups. Needs the restic-peer-* keys in secrets/bandit.yaml (script in
# the runbook).
{
  config,
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  inherit (repoConfig.workstation) homeDirectory;
  secret = name: config.sops.secrets.${name}.path;

  # Home-relative paths to back up; globs and {a,b} are expanded by bash and
  # entries that do not exist are skipped. Edit this list to add or drop data.
  # Deliberately absent: ~/.config/sops/age (the key that opens every secret
  # must not sit on a machine whose key it also opens; keep it offline).
  include = [
    "src"
    ".ssh"
    ".gnupg"
    "Documents"
    "Pictures"
    ".local/share/PrismLauncher/instances/*/minecraft/{saves,config,xaero*,screenshots}"
  ];
  # restic patterns (match at any depth). "result*" and "target" also catch
  # real directories of that name: acceptable for a source-code laptop.
  exclude = [
    "node_modules"
    ".direnv"
    "result"
    "result-*"
    "target"
    ".cache"
    "Downloads"
    ".venv"
    "__pycache__"
    ".gnupg/S.*"
  ];
in {
  bandit.resticPeerServer = {
    enable = true;
    listenIp = repoConfig.lab.workstationTailscaleIp;
    peerIp = repoConfig.lab.tailscaleIp;
    peerUser = "lab"; # the lab's repository: /var/lib/restic-peer/lab
    dataDir = "/var/lib/restic-peer";
    # Quota so the lab cannot fill the laptop's disk (150 GiB). Raise it after
    # cleaning up; the lab's job fails loudly when it is hit.
    maxSize = 150 * 1024 * 1024 * 1024;
  };

  sops.secrets = {
    # rest:http://bandit:<password>@<lab tailnet ip>:8000/bandit/
    "restic-peer-repository" = {};
    # Passphrase of the laptop's repository on the lab.
    "restic-peer-password" = {};
  };

  # No pruneOpts: the lab's server is append-only, the lab prunes.
  services.restic.backups.peer = {
    initialize = true;
    repositoryFile = secret "restic-peer-repository";
    passwordFile = secret "restic-peer-password";
    inherit exclude;
    extraBackupArgs = ["--exclude-caches"];
    dynamicFilesFrom = ''
      #!${pkgs.bash}/bin/bash
      shopt -s nullglob
      for p in ${lib.concatMapStringsSep " " (i: "\"${homeDirectory}\"/${i}") include}; do
        echo "$p"
      done
    '';
    # Several tries a day: runs skipped on battery or while the lab is
    # unreachable are made up at the next one. Extra runs are incremental.
    timerConfig = {
      OnCalendar = ["11:30" "15:30" "20:30"];
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.services.restic-backups-peer = {
    after = ["tailscaled.service"];
    unitConfig = {
      ConditionACPower = true; # skipped on battery
      StartLimitIntervalSec = "2h";
      StartLimitBurst = 4;
    };
    serviceConfig = {
      Restart = "on-failure"; # lab unreachable: retry in 20 min
      RestartSec = "20min";
      # 3 = snapshot saved but some files vanished/unreadable while a live
      # desktop was running; still a usable backup.
      SuccessExitStatus = 3;
      Nice = 10;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "12h";
    };
  };
}
