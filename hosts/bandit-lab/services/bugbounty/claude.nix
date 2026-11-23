# Claude Code's own account on bandit-lab, SSH key only, from the owner's phone and
# laptop over Tailscale (sshd listens on tailscale0 only). Without asking it may read
# logs and unit states, build configurations (nix build, nixos-rebuild build) and start
# exactly one root unit, bugbounty-dry, which runs dry-activate of the deployed mode
# switch. Deploys, `bugbounty on/off` and stopping services stay with the owner: this
# account has no sudo (ci/local-privilege.nix forbids NOPASSWD anyway) and no group
# that is root in disguise (wheel, docker). Guide: docs/runbooks/claude-on-lab.md.
{
  lib,
  repoConfig,
  ...
}: let
  name = "claude";
  addresses = [repoConfig.workstation.phoneTailscaleIp repoConfig.lab.workstationTailscaleIp];
  # One public key per device that runs Claude Code; the private halves stay there.
  keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINCiKB1nkg3JZ+tWpfBR7EHJ0tbmHgmlMMGDBTtE7W83 claude@pong"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIgSmn9yaWI8f5eIQD28EO7broctwAHbMNX/Y1UsXlt claude@bandit"
  ];
in {
  users.users.${name} = {
    isNormalUser = true;
    description = "Claude Code (read-only operator)";
    extraGroups = ["systemd-journal"];
    # no rootless containers; only vino gets an automatic subuid range (ci/lab-surface.nix)
    autoSubUidGidRange = false;
    openssh.authorizedKeys.keys = map (k: ''from="${lib.concatStringsSep "," addresses}" ${k}'') keys;
  };

  services.openssh.settings.AllowUsers = map (a: "${name}@${a}") addresses;

  # Builds through the daemon without being trusted (trusted-users would be root).
  nix.settings.allowed-users = [name];

  security.polkit.enable = true;
  security.polkit.extraConfig = lib.mkAfter ''
    // claude (Claude Code, services/bugbounty/claude.nix) may start bugbounty-dry and nothing else.
    polkit.addRule(function (action, subject) {
      if (subject.user !== "${name}") return polkit.Result.NOT_HANDLED;
      if (action.id === "org.freedesktop.systemd1.manage-units" &&
          action.lookup("verb") === "start" &&
          action.lookup("unit") === "bugbounty-dry.service")
        return polkit.Result.YES;
      return polkit.Result.NO;
    });
  '';
}
