# `lab-apply` (docs/runbooks/bandit-lab-updates.md): deploy bandit-lab's signed main now, with the
# finger on the Framework instead of the lab's sudo password. sudo here (pam_fprintd: finger, password
# as fallback) gates a key only root can read; bandit-lab accepts that key for one forced command,
# `lab-update apply` as root, which deploys only fast-forwards signed by the owner. sudo on the lab keeps
# its password and nothing gets NOPASSWD (ci/local-privilege.nix).
{
  pkgs,
  config,
  ...
}: let
  dir = "/var/lib/lab-apply";
  labApply = pkgs.writeShellScriptBin "lab-apply" ''
    set -euo pipefail
    [[ $# -eq 0 ]] || { echo "usage: lab-apply   (deploys the signed main to bandit-lab now)" >&2; exit 2; }
    [[ $EUID -eq 0 ]] || exec /run/wrappers/bin/sudo "$0"
    exec ${pkgs.openssh}/bin/ssh -i ${dir}/key -o IdentitiesOnly=yes -o BatchMode=yes \
      -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/etc/ssh/ssh_known_hosts \
      root@${config.bandit.lab.tailscaleIp}
  '';
in {
  environment.systemPackages = [labApply];

  programs.ssh.knownHosts.bandit-lab = {
    hostNames = ["bandit-lab" config.bandit.lab.tailscaleIp];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGWHV2AnprciQwc7oWn0XQsZrOUF9coK0RJtL8jrjpPL";
  };

  # Made here once and never copied anywhere: bandit-lab lists the public half (key.pub, world-readable).
  systemd.services.lab-apply-key = {
    description = "Create the root-only key for lab-apply";
    wantedBy = ["multi-user.target"];
    unitConfig.ConditionPathExists = "!${dir}/key";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "lab-apply";
      StateDirectoryMode = "0711";
      UMask = "0077";
    };
    script = ''
      ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C lab-apply@bandit -f ${dir}/key
      chmod 0644 ${dir}/key.pub
    '';
  };
}
