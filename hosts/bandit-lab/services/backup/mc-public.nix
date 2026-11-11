# The public Minecraft world's backup (bandit-craft docs/specs/2026-11-10-public-anarchy-world.md,
# "Longevity"; runbook bandit-craft docs/runbooks/minecraft/PUBLIC.md). Its own restic job into the lab's
# peer repository, apart from the peer job on purpose: a public world that will not flush (lag machine,
# crashed server) fails this run only, never the one that carries Vaultwarden and the private world.
# The host takes the copy: saves are flushed and frozen through the container's console
# (minecraft-snapshot with MC_MACHINE), so nothing is added inside the box and it gets no secret.
{
  config,
  pkgs,
  inputs,
  ...
}: let
  staging = "/var/backup/restic-staging-mc-public";
  snapshot = "${(import "${inputs.bandit-craft}/hosts/bandit-lab/services/minecraft/scripts.nix" {inherit pkgs;}).snapshot}/bin/minecraft-snapshot";
  secret = name: config.sops.secrets.${name}.path;
in {
  # No pruneOpts: the laptop's server is append-only, the laptop prunes (peer.nix).
  services.restic.backups.mc-public = {
    initialize = true;
    repositoryFile = secret "restic-peer-repository";
    passwordFile = secret "restic-peer-password";
    paths = [staging];
    extraBackupArgs = ["--exclude-caches"];
    # Paper's directory only: the worlds, the whitelist and bans, the plugins' data. Velocity holds
    # nothing that is not generated (its forwarding secret is made anew by minecraft-public-secret).
    # Its own lock: the private world's snapshot may run at the same time.
    backupPrepareCommand = ''
      set -euo pipefail
      find ${staging} -mindepth 1 -delete
      MC_MACHINE=mc-public MC_UNIT=minecraft-server-paper MC_DATA=/srv/mc-public/data/paper \
        MC_LOCK=/run/minecraft-snapshot-mc-public.lock ${snapshot} ${staging}/paper
    '';
    backupCleanupCommand = "find ${staging} -mindepth 1 -delete";
    timerConfig = {
      OnCalendar = "06:30"; # after the 05:30 peer window
      Persistent = true;
      RandomizedDelaySec = "20m";
    };
  };

  systemd = {
    tmpfiles.rules = ["d ${staging} 0700 root root -"];
    services.restic-backups-mc-public = {
      after = ["restic-backups-peer.service" "container@mc-public.service" "tailscaled.service"];
      # As for the peer job: the laptop may be asleep or off the tailnet.
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
