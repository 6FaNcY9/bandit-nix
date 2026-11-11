# Two-way link with the owner's phone (docs: `handy` on the laptop, `ssh pc` /
# `pc-screen` in Termux on the phone). sshd exists for that phone only: the
# firewall admits just its tailnet /32 on tailscale0, key-only, no root.
{config, ...}: let
  inherit (config.bandit.workstation) username phoneTailscaleIp;
  rule = "-i tailscale0 -s ${phoneTailscaleIp}/32 -p tcp --dport 22 -j nixos-fw-accept";
in {
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [username];
    };
  };

  networking.firewall = {
    extraCommands = "iptables -w -A nixos-fw ${rule}";
    extraStopCommands = "iptables -w -D nixos-fw ${rule} || true";
  };

  users.users.${username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBtD+QBx9uxrRUIc03jxejS62Mdhl2kgz4mRbkPyeq8S phone@pong"
  ];
}
