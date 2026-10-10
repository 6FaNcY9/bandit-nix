{
  config,
  lib,
  pkgs,
  ...
}: {
  options.bandit-lab.slayerTunnel.enable = lib.mkEnableOption "idle Slayer PC inference over a loopback SSH tunnel";
  config = lib.mkIf config.bandit-lab.slayerTunnel.enable {
    sops.secrets."slayer-tunnel-key" = {};
    programs.ssh.knownHosts.slayerpc = {
      hostNames = ["100.76.40.98"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIQqLzKYo4S6Ldqfyt9kWOUPNg82r8/QsJTKOPsqN1G9";
    };
    users.users.slayer-tunnel = {
      isSystemUser = true;
      group = "slayer-tunnel";
    };
    users.groups.slayer-tunnel = {};
    systemd.services.slayer-tunnel = {
      description = "Loopback-only Slayer inference tunnel";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "tailscaled.service"];
      wants = ["network-online.target" "tailscaled.service"];
      serviceConfig = {
        ExecStart = "${pkgs.openssh}/bin/ssh -NT -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/etc/ssh/ssh_known_hosts -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -i %d/slayer-tunnel-key -L 127.0.0.1:18081:127.0.0.1:8081 yassi@100.76.40.98";
        LoadCredential = "slayer-tunnel-key:${config.sops.secrets."slayer-tunnel-key".path}";
        # ssh needs a passwd entry (getpwuid); DynamicUser gave "No user exists for uid" and the deploy rolled back.
        User = "slayer-tunnel";
        Group = "slayer-tunnel";
        Restart = "always";
        RestartSec = 30;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
        IPAddressAllow = ["localhost" "100.76.40.98"];
        IPAddressDeny = "any";
      };
    };
  };
}
