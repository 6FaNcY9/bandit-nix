# Peer backups, lab side (docs/runbooks/backup-peer.md): the lab pushes the same
# data as the Backblaze job to a restic REST server on the laptop, and hosts the
# laptop's backups in /srv/backup/restic-peer. Always on: a free second copy.
# Needs the restic-peer-* keys in secrets/lab.yaml (script in the runbook).
{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  shared = import ./shared.nix {inherit pkgs;};
  staging = "/var/backup/restic-staging-peer";
  secret = name: config.sops.secrets.${name}.path;
in {
  bandit.resticPeerServer = {
    enable = true;
    listenIp = repoConfig.lab.tailscaleIp;
    peerIp = repoConfig.lab.workstationTailscaleIp;
    peerUser = "bandit"; # the laptop's repository: /srv/backup/restic-peer/bandit
    dataDir = "/srv/backup/restic-peer";
  };

  sops.secrets = {
    # Full repository URL with the laptop's htpasswd password for user `lab`:
    # rest:http://lab:<password>@<laptop tailnet ip>:8000/lab/
    "restic-peer-repository" = {};
    # Passphrase of the lab's repository on the laptop.
    "restic-peer-password" = {};
  };

  # No pruneOpts: the laptop's server is append-only, the laptop prunes.
  services.restic.backups.peer = {
    initialize = true;
    repositoryFile = secret "restic-peer-repository";
    passwordFile = secret "restic-peer-password";
    paths = shared.paths staging;
    extraBackupArgs = ["--exclude-caches"];
    backupPrepareCommand = shared.prepare staging;
    backupCleanupCommand = "find ${staging} -mindepth 1 -delete";
    timerConfig = {
      OnCalendar = "05:30"; # after the 04:30 Backblaze window (if enabled)
      Persistent = true;
      RandomizedDelaySec = "20m";
    };
  };

  systemd = {
    tmpfiles.rules = ["d ${staging} 0700 root root -"];

    services.restic-backups-peer = {
      # Never overlap the Backblaze job (both call minecraft-snapshot).
      after = shared.after ++ ["restic-backups-lab.service" "tailscaled.service"];
      # Laptop asleep or off the tailnet: retry hourly. After 6 failed starts in
      # 12 h the unit stays failed (alert) until the next timer run.
      unitConfig = {
        StartLimitIntervalSec = "12h";
        StartLimitBurst = 6;
      };
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "1h";
        TimeoutStartSec = "12h";
      };
    };
  };
}
