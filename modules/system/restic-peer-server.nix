# Append-only restic REST server for the peer backup (docs/runbooks/backup-peer.md).
# One instance per host: it listens on this host's own tailnet address only, the
# firewall admits just the peer's tailnet /32 on tailscale0, and the peer gets a
# private repository (<dataDir>/<peerUser>) behind a htpasswd entry from SOPS.
# The peer can add snapshots but never delete them; this host prunes locally.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.bandit.resticPeerServer;
  inherit (config.bandit.backupPeer) port retention;
  ruleFor = ip: "-i tailscale0 -s ${ip}/32 -p tcp --dport ${toString port} -j nixos-fw-accept";
  rules = [(ruleFor cfg.peerIp)] ++ lib.concatMap (p: map ruleFor p.ips) (lib.attrValues cfg.extraPeers);
  secretPath = name: config.sops.secrets.${name}.path;
  # Append-only means the peer cannot forget; retention is applied here, on the
  # repository files, with the peer's repository password.
  pruneUnit = unit: name: passwordFile: {
    description = "Apply retention to restic repository ${name}";
    environment = {
      RESTIC_REPOSITORY = "${cfg.dataDir}/${name}";
      RESTIC_PASSWORD_FILE = passwordFile;
      RESTIC_CACHE_DIR = "/var/cache/${unit}";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "restic";
      Group = "restic";
      CacheDirectory = unit;
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
  pruneTimer = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "Sun 07:30";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
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
    extraPeers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          ips = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Tailnet addresses admitted for this peer.";
          };
          prunePasswordSecret = lib.mkOption {
            type = lib.types.str;
            description = "SOPS secret holding the peer repository password, for the local prune.";
          };
        };
      });
      default = {};
      description = "Further append-only peers; key = htpasswd user = repository directory under dataDir.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets =
      {
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
      }
      // lib.mapAttrs' (_: p:
        lib.nameValuePair p.prunePasswordSecret {
          owner = "restic";
          mode = "0400";
        })
      cfg.extraPeers;

    services.restic.server = {
      enable = true;
      listenAddress = "${cfg.listenIp}:${toString port}";
      inherit (cfg) dataDir;
      appendOnly = true;
      privateRepos = true;
      htpasswd-file = config.sops.secrets."restic-peer-htpasswd".path;
      extraFlags = ["--log" "-"] ++ lib.optionals (cfg.maxSize != null) ["--max-size" (toString cfg.maxSize)];
    };
    # The socket unit binds with FreeBind, so it starts before tailscaled has
    # assigned the address; no tailscaled ordering or retry loop is needed.

    networking.firewall = {
      extraCommands = lib.concatMapStringsSep "\n" (r: "iptables -w -A nixos-fw ${r}") rules;
      extraStopCommands = lib.concatMapStringsSep "\n" (r: "iptables -w -D nixos-fw ${r} || true") rules;
    };

    systemd = {
      tmpfiles.rules = [
        "d ${dirOf cfg.dataDir} 0755 root root -"
        "d ${cfg.dataDir} 0750 restic restic -"
      ];

      services = {restic-peer-prune = pruneUnit "restic-peer-prune" cfg.peerUser (secretPath "restic-peer-prune-password");} // lib.mapAttrs' (n: p: lib.nameValuePair "restic-peer-prune-${n}" (pruneUnit "restic-peer-prune-${n}" n (secretPath p.prunePasswordSecret))) cfg.extraPeers;
      timers = {restic-peer-prune = pruneTimer;} // lib.mapAttrs' (n: _: lib.nameValuePair "restic-peer-prune-${n}" pruneTimer) cfg.extraPeers;
    };
  };
}
