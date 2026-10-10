{
  config,
  lib,
  pkgs,
  ...
}: let
  hosts = lib.filterAttrs (_: host: host.enable) config.bandit-lab.inferenceHosts;
  named = f: lib.mapAttrs' (name: host: lib.nameValuePair "${name}-tunnel" (f name host)) hosts;
in {
  options.bandit-lab = {
    slayerTunnel.enable = lib.mkEnableOption "idle Slayer PC inference over a loopback SSH tunnel";
    inferenceHosts = lib.mkOption {
      default = {};
      description = "Gaming PCs serving Andy on loopback port 8081; each needs an existing <name>-tunnel-key SOPS secret.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this inference tunnel";
          address = lib.mkOption {type = lib.types.strMatching "100\\.[0-9]+\\.[0-9]+\\.[0-9]+";};
          user = lib.mkOption {type = lib.types.strMatching "[a-zA-Z0-9_.-]+";};
          hostKey = lib.mkOption {type = lib.types.str;};
          localPort = lib.mkOption {type = lib.types.port;};
        };
      });
    };
  };
  config = {
    # Compatibility with the deployed option, identity, port and secret name.
    bandit-lab.inferenceHosts.slayer = {
      enable = lib.mkDefault config.bandit-lab.slayerTunnel.enable;
      address = lib.mkDefault "100.76.40.98";
      user = lib.mkDefault "yassi";
      hostKey = lib.mkDefault "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIQqLzKYo4S6Ldqfyt9kWOUPNg82r8/QsJTKOPsqN1G9";
      localPort = lib.mkDefault 18081;
    };
    assertions = [
      {
        assertion = lib.all (name: builtins.match "[a-z][a-z0-9_-]{0,24}" name != null) (builtins.attrNames hosts);
        message = "Inference host names must start with a lowercase letter and contain at most 25 lowercase letters, digits, underscores or hyphens.";
      }
      {
        assertion = builtins.length (lib.unique (map (h: h.localPort) (builtins.attrValues hosts))) == builtins.length (builtins.attrNames hosts);
        message = "Inference hosts must have distinct local ports.";
      }
    ];
    sops.secrets = lib.mapAttrs' (name: _: lib.nameValuePair "${name}-tunnel-key" {}) hosts;
    programs.ssh.knownHosts = named (_: host: {
      hostNames = [host.address];
      publicKey = host.hostKey;
    });
    users.users = named (name: _: {
      isSystemUser = true;
      group = "${name}-tunnel";
    });
    users.groups = named (_: _: {});
    systemd.services = named (name: host: {
      description = "Loopback-only ${name} inference tunnel";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "tailscaled.service"];
      wants = ["network-online.target" "tailscaled.service"];
      serviceConfig = {
        ExecStart = "${pkgs.openssh}/bin/ssh -NT -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/etc/ssh/ssh_known_hosts -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -i %d/${name}-tunnel-key -L 127.0.0.1:${toString host.localPort}:127.0.0.1:8081 ${host.user}@${host.address}";
        LoadCredential = "${name}-tunnel-key:${config.sops.secrets."${name}-tunnel-key".path}";
        # ssh needs a passwd entry (getpwuid); DynamicUser broke authentication.
        User = "${name}-tunnel";
        Group = "${name}-tunnel";
        Restart = "always";
        RestartSec = 30;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
        IPAddressAllow = ["localhost" host.address];
        IPAddressDeny = "any";
      };
    });
  };
}
