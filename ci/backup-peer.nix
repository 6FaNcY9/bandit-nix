# Peer backup contract (docs/runbooks/backup-peer.md). Evaluation-time only:
# on both hosts the REST server binds just the host's own tailnet address,
# runs append-only with private repos, the firewall admits only the peer's /32
# on tailscale0, and every restic repository/password is a sops-delivered file
# (a rest: URL carries a password, so it must never enter the Nix store).
{
  pkgs,
  lib,
  repoConfig,
  hosts,
}: let
  port = toString repoConfig.backupPeer.port;
  expect = {
    bandit = {
      self = repoConfig.lab.workstationTailscaleIp;
      peer = repoConfig.lab.tailscaleIp;
    };
    bandit-lab = {
      self = repoConfig.lab.tailscaleIp;
      peer = repoConfig.lab.workstationTailscaleIp;
    };
  };
  rule = peer: "iptables -w -A nixos-fw -i tailscale0 -s ${peer}/32 -p tcp --dport ${port} -j nixos-fw-accept";
  checkHost = name: {
    self,
    peer,
  }: let
    cfg = hosts.${name}.config;
    srv = cfg.services.restic.server;
    job = cfg.services.restic.backups.peer;
    sops = cfg.sops.secrets;
    msg = m: "${name}: ${m}";
  in
    assert lib.assertMsg srv.enable (msg "restic REST server must be enabled");
    assert lib.assertMsg (srv.listenAddress == "${self}:${port}") (msg "rest-server must bind only ${self}:${port}, got ${srv.listenAddress}");
    assert lib.assertMsg (cfg.systemd.sockets.restic-rest-server.listenStreams == ["${self}:${port}"]) (msg "socket must listen only on the tailnet address");
    assert lib.assertMsg srv.appendOnly (msg "rest-server must be append-only");
    assert lib.assertMsg srv.privateRepos (msg "rest-server must use private repos");
    assert lib.assertMsg (srv.htpasswd-file == sops."restic-peer-htpasswd".path && lib.hasPrefix "/run/secrets/" srv.htpasswd-file) (msg "htpasswd must come from sops");
    assert lib.assertMsg (lib.hasInfix (rule peer) cfg.networking.firewall.extraCommands) (msg "firewall rule must be tailscale0 + ${peer}/32 + port ${port}");
    assert lib.assertMsg (!(lib.hasInfix "--dport ${port}" (toString cfg.networking.firewall.allowedTCPPorts)) && !(lib.any (i: lib.elem repoConfig.backupPeer.port i.allowedTCPPorts) (lib.attrValues cfg.networking.firewall.interfaces))) (msg "the REST port must not be opened by allowedTCPPorts");
    assert lib.assertMsg (job.repository == null && !(job ? password)) (msg "repository and password must not be inline Nix strings");
    assert lib.assertMsg (lib.hasPrefix "/run/secrets/" job.repositoryFile && lib.hasPrefix "/run/secrets/" job.passwordFile) (msg "peer repository and password must be sops files");
    assert lib.assertMsg (job.pruneOpts == []) (msg "peer job must not prune (peer server is append-only)");
    assert lib.assertMsg (cfg.systemd.timers ? restic-peer-prune) (msg "local retention timer missing");
      lib.sort lib.lessThan (lib.filter (lib.hasPrefix "restic-peer-") (lib.attrNames sops));
  declared = lib.mapAttrs checkHost expect;
in
  assert lib.assertMsg (declared.bandit == declared.bandit-lab && declared.bandit == ["restic-peer-htpasswd" "restic-peer-password" "restic-peer-prune-password" "restic-peer-repository"]) "each host must declare exactly the four restic-peer-* secrets";
    pkgs.runCommand "backup-peer" {} ''
      touch "$out"
    ''
