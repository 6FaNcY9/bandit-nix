{pkgs, ...}: let
  repoDir = "/etc/nixos/bandit-nix";
  repositoryUrl = "https://github.com/6FaNcY9/bandit-nix.git";
  signingKeyFingerprint = "4D8770567A65FE1369E2BCC1611871842A8C1619";

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

    # Concurrent runs must be a harmless no-op, never a failure: the apply
    # timer can fire while a manual apply (or an activation-started unit) is
    # mid-switch, and a failing second instance makes switch-to-configuration
    # return non-zero, which aborts the in-flight update.
    exec 9>/run/lab-update.lock
    if ! ${pkgs.util-linux}/bin/flock -n 9; then
      echo "another lab-update run is in progress; nothing to do"
      exit 0
    fi

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

    # The apply timer runs unattended as root, so only commits signed by the
    # owner's GPG key may be built and activated — a compromised GitHub
    # account alone must not be able to push code that runs here.
    export PATH="${pkgs.gnupg}/bin:$PATH"
    export GNUPGHOME
    GNUPGHOME="$(${pkgs.coreutils}/bin/mktemp -d)"
    trap '${pkgs.coreutils}/bin/rm -rf "$GNUPGHOME"' EXIT
    ${pkgs.gnupg}/bin/gpg --batch --quiet --import ${./lab-update-signing-key.asc}
    echo "${signingKeyFingerprint}:6:" | ${pkgs.gnupg}/bin/gpg --batch --quiet --import-ownertrust
    if ! "$git" -c safe.directory="$repo" -C "$repo" verify-commit "$after"; then
      echo "Refusing commit $after: not signed by ${signingKeyFingerprint}" >&2
      exit 1
    fi
    # The checkout is a clean read-only mirror — all changes are authored on
    # the laptop — so rewritten upstream history (rebase/force-push) must not
    # wedge the updater. Warn now and reset the mirror to the deployed commit
    # once the candidate system has been activated successfully.
    non_ff=0
    if ! "$git" -c safe.directory="$repo" -C "$repo" merge-base --is-ancestor "$before" "$after"; then
      echo "Warning: non-fast-forward update $before -> $after; will hard-reset the mirror checkout after a successful switch" >&2
      non_ff=1
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

    if [[ "$non_ff" == "1" ]]; then
      if ! "$git" -c safe.directory="$repo" -C "$repo" reset --hard "$after"; then
        restore_current
        exit 1
      fi
    elif ! "$git" -c safe.directory="$repo" -C "$repo" merge --ff-only "$after"; then
      restore_current
      exit 1
    fi
    echo "bandit-lab activated and recorded at $after"
  '';
in {
  environment.systemPackages = [labUpdate];

  systemd = {
    services = {
      lab-update-check = {
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

      # Unattended apply: the lab-update script builds the candidate,
      # activates it with switch-to-configuration test, gates on
      # bandit-lab-health, and rolls back on any failure, so running it from
      # a timer is safe. Disable with
      # `systemctl disable --now lab-update-apply.timer` if manual control is
      # needed.
      lab-update-apply = {
        description = "Apply available bandit-lab configuration updates";
        wants = ["network-online.target"];
        after = ["network-online.target" "sops-nix.service"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${labUpdate}/bin/lab-update apply";
          User = "root";
          Environment = ["HOME=/root"];
        };
      };
    };

    timers = {
      lab-update-check = {
        description = "Poll GitHub for bandit-lab configuration updates";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnActiveSec = "2min";
          OnUnitActiveSec = "10min";
          Persistent = true;
        };
      };

      lab-update-apply = {
        description = "Automatically apply bandit-lab configuration updates";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnActiveSec = "10min";
          OnUnitActiveSec = "1h";
          RandomizedDelaySec = "10min";
          Persistent = true;
        };
      };
    };
  };
}
