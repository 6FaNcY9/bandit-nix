{pkgs, ...}: let
  repoDir = "/etc/nixos/bandit-nix";
  repositoryUrl = "https://github.com/6FaNcY9/bandit-nix.git";

  labUpdate = pkgs.writeShellScriptBin "lab-update" ''
    set -euo pipefail

    mode="''${1:-check}"
    repo="${repoDir}"
    git="${pkgs.git}/bin/git"

    case "$mode" in
      check|apply) ;;
      *)
        echo "Usage: lab-update [check|apply]" >&2
        exit 2
        ;;
    esac

    if [[ ! -d "$repo/.git" ]]; then
      install -d -m 0755 "$(dirname "$repo")"
      "$git" clone ${repositoryUrl} "$repo"
    fi

    # This repository is public. Keep unattended reads independent of a
    # host-local deploy key and never grant the updater push credentials.
    "$git" -c safe.directory="$repo" -C "$repo" remote set-url origin ${repositoryUrl}

    before=$("$git" -c safe.directory="$repo" -C "$repo" rev-parse HEAD)
    "$git" -c safe.directory="$repo" -C "$repo" fetch origin main --quiet
    after=$("$git" -c safe.directory="$repo" -C "$repo" rev-parse origin/main)

    if [[ "$before" == "$after" ]]; then
      echo "bandit-lab is already at $before"
      exit 0
    fi

    echo "bandit-lab update available: $before -> $after"
    if [[ "$mode" == "check" ]]; then
      exit 0
    fi

    if ! "$git" -c safe.directory="$repo" -C "$repo" diff --quiet \
      || ! "$git" -c safe.directory="$repo" -C "$repo" diff --cached --quiet; then
      echo "Refusing to update a dirty checkout: $repo" >&2
      exit 1
    fi
    if ! "$git" -c safe.directory="$repo" -C "$repo" merge-base --is-ancestor "$before" "$after"; then
      echo "Refusing non-fast-forward update: $before -> $after" >&2
      exit 1
    fi

    current_system="$(readlink -f /run/current-system)"
    candidate="git+file://$repo?rev=$after"
    echo "Building candidate $after"
    candidate_system="$(${pkgs.nix}/bin/nix build \
      --max-jobs 2 \
      --cores 4 \
      --no-link \
      --print-out-paths \
      "$candidate#nixosConfigurations.bandit-lab.config.system.build.toplevel")"

    restore_current() {
      echo "Restoring $current_system" >&2
      ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --set "$current_system"
      "$current_system/bin/switch-to-configuration" switch
    }

    echo "Testing candidate configuration"
    if ! "$candidate_system/bin/switch-to-configuration" test; then
      "$current_system/bin/switch-to-configuration" test || true
      exit 1
    fi
    if ! "$candidate_system/sw/bin/bandit-lab-health"; then
      "$current_system/bin/switch-to-configuration" test || true
      exit 1
    fi

    echo "Activating candidate configuration"
    ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --set "$candidate_system"
    if ! "$candidate_system/bin/switch-to-configuration" switch; then
      restore_current
      exit 1
    fi
    if ! "$candidate_system/sw/bin/bandit-lab-health"; then
      restore_current
      exit 1
    fi

    if ! "$git" -c safe.directory="$repo" -C "$repo" merge --ff-only "$after"; then
      restore_current
      exit 1
    fi
    echo "bandit-lab activated and recorded at $after"
  '';
in {
  environment.systemPackages = [labUpdate];

  systemd.services.lab-update-check = {
    description = "Check bandit-lab for available configuration updates";
    wants = ["network-online.target"];
    after = ["network-online.target" "sops-nix.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${labUpdate}/bin/lab-update check";
      User = "root";
      Environment = ["HOME=/root"];
    };
  };

  systemd.timers.lab-update-check = {
    description = "Poll GitHub for bandit-lab configuration updates";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
      Persistent = true;
    };
  };
}
