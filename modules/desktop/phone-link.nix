# Two-way link with the owner's phone (docs: `handy` on the laptop, `ssh pc` /
# `pc-screen` in Termux on the phone). sshd exists for that phone and the
# owner's station slayerpc only: the firewall admits just their tailnet /32s
# on tailscale0, key-only, no root.
{
  config,
  lib,
  ...
}: let
  inherit (config.bandit.workstation) username phoneTailscaleIp;
  # slayerpc, Windows account vino (owner 2026-11-15); its key is bound to this address.
  slayerTailscaleIp = "100.76.40.98";
  # Not 22: Tailscale SSH answers there on the tailnet address and asks for a
  # browser check, which a phone script cannot pass.
  port = 2222;
  rules = map (ip: "-i tailscale0 -s ${ip}/32 -p tcp --dport ${toString port} -j nixos-fw-accept") [phoneTailscaleIp slayerTailscaleIp];
in {
  services.openssh = {
    enable = true;
    ports = [port];
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [username];
    };
  };

  networking.firewall = {
    extraCommands = lib.concatMapStringsSep "\n" (rule: "iptables -w -A nixos-fw ${rule}") rules;
    extraStopCommands = lib.concatMapStringsSep "\n" (rule: "iptables -w -D nixos-fw ${rule} || true") rules;
  };

  users.users.${username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBtD+QBx9uxrRUIc03jxejS62Mdhl2kgz4mRbkPyeq8S phone@pong"
    ''from="${slayerTailscaleIp}" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJW6a1Ku+KiolefVmYbJPYYin0wQBul7waOi6rxnf9HW vino@SlayerPC''
  ];
}
