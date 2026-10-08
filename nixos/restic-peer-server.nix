# Append-only restic REST server for the peer backup (docs/runbooks/backup-peer.md).
# One instance per host: it listens on this host's own tailnet address only, the
# firewall admits just the peer's tailnet /32 on tailscale0, and the peer gets a
# private repository (<dataDir>/<peerUser>) behind a htpasswd entry from SOPS.
# The peer can add snapshots but never delete them; this host prunes locally.
{
  config,
  lib,
  pkgs,
  repoConfig,
  ...
}: let
  cfg = config.bandit.resticPeerServer;
  inherit (repoConfig.backupPeer) port retention;
  fwRule = "-i tailscale0 -s ${cfg.peerIp}/32 -p tcp --dport ${toString port} -j nixos-fw-accept";
in {
  options.bandit.resticPeerServer = {
    enable = lib.mkEnableOption "append-only restic REST server for the peer host";
    listenIp = lib.mkOption {
      type = lib.types.str;
      description = "This host's own tailnet address; the only address the server binds.";
    };
    peerIp = lib.mkOption {
      type = lib.types.str;
      description = "Tailnet address of the one peer allowed to connect.";
    };
    peerUser = lib.mkOption {
      type = lib.types.str;
      description = "htpasswd user of the peer; its repository lives in <dataDir>/<peerUser>.";
    };
    dataDir = lib.mkOption {type = lib.types.path;};
    maxSize = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Repository quota in bytes (rest-server --max-size); null disables it.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      # htpasswd line(s) for the peer (bcrypt), read by the rest-server.
      "restic-peer-htpasswd" = {
        owner = "restic";
        mode = "0400";
      };
      # Password of the peer's repository, needed only for the local prune.
      "restic-peer-prune-password" = {
        owner = "restic";
        mode = "0400";
      };
    };

    services.restic.server = {
      enable = true;
      listenAddress = "${cfg.listenIp}:${toString port}";
      inherit (cfg) dataDir;
      appendOnly = true;
      privateRepos = true;
      htpasswd-file = config.sops.secrets."restic-peer-htpasswd".path;
      extraFlags = lib.optionals (cfg.maxSize != null) ["--max-size" (toString cfg.maxSize)];
    };
    # The socket unit binds with FreeBind, so it starts before tailscaled has
    # assigned the address; no tailscaled ordering or retry loop is needed.

    networking.firewall = {
      extraCommands = "iptables -w -A nixos-fw ${fwRule}";
      extraStopCommands = "iptables -w -D nixos-fw ${fwRule} || true";
    };

    systemd = {
      tmpfiles.rules = [
        "d ${dirOf cfg.dataDir} 0755 root root -"
        "d ${cfg.dataDir} 0750 restic restic -"
      ];

      # Append-only means the peer cannot forget; apply the retention here, on
      # the repository files, with the peer's repository password.
      services.restic-peer-prune = {
        description = "Apply retention to the peer's restic repository";
        environment = {
          RESTIC_REPOSITORY = "${cfg.dataDir}/${cfg.peerUser}";
          RESTIC_PASSWORD_FILE = config.sops.secrets."restic-peer-prune-password".path;
          RESTIC_CACHE_DIR = "/var/cache/restic-peer-prune";
        };
        serviceConfig = {
          Type = "oneshot";
          User = "restic";
          Group = "restic";
          CacheDirectory = "restic-peer-prune";
          NoNewPrivileges = true;
          PrivateTmp = true;
          TimeoutStartSec = "6h";
        };
        script = ''
          # Nothing to prune before the peer's first backup.
          [ -e "$RESTIC_REPOSITORY/config" ] || exit 0
          ${pkgs.restic}/bin/restic --retry-lock 2h forget --prune ${lib.concatStringsSep " " retention}
        '';
      };
      timers.restic-peer-prune = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "Sun 07:30";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };
    };
  };
}
