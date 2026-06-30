{pkgs, lib, ...}: let
  repoDir = "/etc/nixos/bandit-nix";

  rebuildScript = pkgs.writeShellScript "auto-rebuild" ''
    set -e
    REPO="${repoDir}"

    # Clone if missing
    if [[ ! -d "$REPO/.git" ]]; then
      ${pkgs.git}/bin/git clone git@github.com:6FaNcY9/bandit-nix.git "$REPO"
    fi

    cd "$REPO"
    BEFORE=$(${pkgs.git}/bin/git rev-parse HEAD)
    ${pkgs.git}/bin/git fetch origin main --quiet
    AFTER=$(${pkgs.git}/bin/git rev-parse origin/main)

    [[ "$BEFORE" == "$AFTER" ]] && exit 0  # nothing new

    echo "New commits detected — rebuilding bandit-lab..."
    ${pkgs.git}/bin/git merge --ff-only origin/main
    /run/current-system/sw/bin/nixos-rebuild switch \
      --flake "${repoDir}#bandit-lab" \
      --log-format internal-json 2>&1 \
      | ${pkgs.nix}/bin/nix log-format
  '';
in {
  # Allow vino to run nixos-rebuild without password
  security.sudo.extraRules = [{
    users = ["vino"];
    commands = [{
      command = "/run/current-system/sw/bin/nixos-rebuild";
      options = ["NOPASSWD"];
    }];
  }];

  systemd.services.auto-rebuild = {
    description = "Auto nixos-rebuild on new git commits";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${rebuildScript}";
      User = "root";
      Environment = [
        "GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh -i /home/vino/.ssh/github-lab -o StrictHostKeyChecking=accept-new"
        "HOME=/root"
      ];
    };
  };

  systemd.timers.auto-rebuild = {
    description = "Poll git for new commits every 10 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
      Persistent = false;
    };
  };
}
