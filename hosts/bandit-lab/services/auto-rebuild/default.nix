{pkgs, ...}: let
  repoDir = "/etc/nixos/bandit-nix";
  repositoryUrl = "https://github.com/6FaNcY9/bandit-nix.git";
  signingKeyFingerprint = "4D8770567A65FE1369E2BCC1611871842A8C1619";
  phoneSigningKeyFingerprint = "6FC0F17CBA83E7BA06D7C929EE5EB15A5F02387A";

  labUpdate = pkgs.writeShellScriptBin "lab-update" ''
    set -euo pipefail

    mode="''${1:-check}"
    allow_non_ff=0
    repo="${repoDir}"
    git="${pkgs.git}/bin/git"

    usage() {
      echo "Usage: lab-update [check|apply [--allow-non-ff]]" >&2
      exit 2
    }
    [[ $# -le 2 ]] || usage
    case "$mode" in
      check|apply) ;;
      *) usage ;;
    esac
    case "''${2:-}" in
      "") ;;
      --allow-non-ff)
        # Manual override for a reviewed history rewrite. Never used by the
        # systemd units, and a flake check keeps it out of every ExecStart.
        [[ "$mode" == apply ]] || usage
        # systemd sets INVOCATION_ID for every unit (timers, systemd-run,
        # wrapper scripts the flake lint cannot see into). sudo resets the
        # environment, so a human running `sudo lab-update apply --allow-non-ff`
        # is unaffected.
        if [[ -n "''${INVOCATION_ID:-}" ]]; then
          echo "--allow-non-ff is manual-only and refused inside a systemd unit" >&2
          exit 2
        fi
        allow_non_ff=1
        ;;
      *) usage ;;
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
      "$git" clone --no-tags --single-branch --branch main ${repositoryUrl} "$repo"
    fi

    # This repository is public. Keep unattended reads independent of a
    # host-local deploy key and never grant the updater push credentials.
    "$git" -c safe.directory="$repo" -C "$repo" remote set-url origin ${repositoryUrl}

    before=$("$git" -c safe.directory="$repo" -C "$repo" rev-parse HEAD)
    # Fetch with an explicit refspec and no tags, and resolve only the fully
    # qualified remote-tracking ref: a bare `origin/main` is ambiguous, and git
    # prefers a TAG of that name (refs/tags/origin/main) over the branch, which
    # would let a pushed tag steer what gets deployed. `^{commit}` peels it.
    "$git" -c safe.directory="$repo" -C "$repo" fetch --no-tags --quiet origin \
      '+refs/heads/main:refs/remotes/origin/main'
    after=$("$git" -c safe.directory="$repo" -C "$repo" rev-parse --verify --quiet \
      'refs/remotes/origin/main^{commit}')

    # Only fast-forwards are deployed. A signed but older commit (downgrade) or
    # rewritten history (force-push) is exactly what a compromised GitHub
    # account could offer, e.g. a commit from before a password rotation.
    update_kind=fast-forward
    if [[ "$before" != "$after" ]] \
      && ! "$git" -c safe.directory="$repo" -C "$repo" merge-base --is-ancestor "$before" "$after"; then
      if "$git" -c safe.directory="$repo" -C "$repo" merge-base --is-ancestor "$after" "$before"; then
        update_kind=downgrade
      else
        update_kind=diverged
      fi
    fi

    if [[ "$mode" == "check" ]]; then
      if [[ "$before" == "$after" ]]; then
        echo "Checkout matches $after; activation status is checked by lab-update apply"
      elif [[ "$update_kind" == fast-forward ]]; then
        echo "Checkout update available: $before -> $after"
      else
        echo "Non-fast-forward ($update_kind) update $before -> $after: lab-update apply will refuse it" >&2
      fi
      exit 0
    fi

    if ! "$git" -c safe.directory="$repo" -C "$repo" diff --quiet \
      || ! "$git" -c safe.directory="$repo" -C "$repo" diff --cached --quiet; then
      echo "Refusing to update a dirty checkout: $repo" >&2
      exit 1
    fi

    if [[ "$update_kind" != fast-forward && "$allow_non_ff" != 1 ]]; then
      echo "Refusing $update_kind update $before -> $after: not a fast-forward of the deployed commit." >&2
      echo "If this rewrite is intended and reviewed, run: lab-update apply --allow-non-ff" >&2
      exit 1
    fi

    # The apply timer runs unattended as root, so only commits signed by the
    # owner's GPG key may be built and activated — a compromised GitHub
    # account alone must not be able to push code that runs here.
    export PATH="${pkgs.gnupg}/bin:$PATH"
    export GNUPGHOME
    GNUPGHOME="$(${pkgs.coreutils}/bin/mktemp -d)"
    rollback_needed=0
    cleanup() {
      status=$?
      trap - EXIT
      if [[ "$rollback_needed" == 1 ]]; then
        echo "Restoring previous boot profile and running configuration" >&2
        if ! ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --set "$previous_profile"; then
          echo "ERROR: could not restore the system profile" >&2
        fi
        if ! "$previous_profile/bin/switch-to-configuration" boot; then
          echo "ERROR: could not restore the boot configuration" >&2
        fi
        if ! "$current_system/bin/switch-to-configuration" test; then
          echo "ERROR: could not restore the running configuration" >&2
        fi
        status=1
      fi
      ${pkgs.coreutils}/bin/rm -rf "$GNUPGHOME"
      exit "$status"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    ${pkgs.gnupg}/bin/gpg --batch --quiet --import ${./lab-update-signing-key.asc} ${./lab-update-phone-signing-key.asc}

    printf '%s\n' "${signingKeyFingerprint}:6:" "${phoneSigningKeyFingerprint}:6:" | ${pkgs.gnupg}/bin/gpg --batch --quiet --import-ownertrust

    if ! "$git" -c safe.directory="$repo" -C "$repo" verify-commit "$after"; then
      echo "Refusing commit $after: not signed by a trusted deployment key" >&2
      exit 1
    fi

    vaultwarden_changes="$($git -c safe.directory="$repo" -C "$repo" diff --name-only "$before" "$after" -- hosts/bandit-lab/services/vaultwarden/)"
    if [[ -n "$vaultwarden_changes" ]]; then
      echo "Refusing automatic activation of $after: hosts/bandit-lab/services/vaultwarden/ changed." >&2
      echo "Automatic rollback does not restore persistent Vaultwarden data; supervised maintenance with a consistent, verified backup is required." >&2
      exit 1
    fi

    # The checkout is a clean read-only mirror, so an explicitly allowed
    # history rewrite (--allow-non-ff) must not wedge the updater: reset the
    # mirror to the deployed commit once the candidate has been activated.
    non_ff=0
    if [[ "$update_kind" != fast-forward ]]; then
      echo "Warning: $update_kind update $before -> $after allowed by --allow-non-ff; will hard-reset the mirror checkout after a successful switch" >&2
      non_ff=1
    fi

    current_system="$(readlink -f /run/current-system)"
    previous_profile="$(readlink -f /nix/var/nix/profiles/system)"
    candidate="git+file://$repo?rev=$after"
    echo "Building candidate $after"
    candidate_system="$(${pkgs.nix}/bin/nix build \
      --max-jobs 2 \
      --cores 4 \
      --no-link \
      --print-out-paths \
      "$candidate#nixosConfigurations.bandit-lab.config.system.build.toplevel")"

    if [[ "$candidate_system" == "$current_system" && "$candidate_system" == "$previous_profile" ]]; then
      echo "Candidate is already running and selected for boot"
      "$candidate_system/sw/bin/bandit-lab-health"
    else
      # From the first test onward, every exit (including signals and a
      # failed profile update) must restore both pre-update states.
      rollback_needed=1
      echo "Testing candidate configuration"
      "$candidate_system/bin/switch-to-configuration" test
      "$candidate_system/sw/bin/bandit-lab-health"

      echo "Activating candidate configuration"
      ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --set "$candidate_system"
      "$candidate_system/bin/switch-to-configuration" switch
      "$candidate_system/sw/bin/bandit-lab-health"
    fi

    if [[ "$non_ff" == "1" ]]; then
      if ! "$git" -c safe.directory="$repo" -C "$repo" reset --hard "$after"; then
        exit 1
      fi
    elif ! "$git" -c safe.directory="$repo" -C "$repo" merge --ff-only "$after"; then
      exit 1
    fi
    rollback_needed=0
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
        # Activation must never (re)start these units: a mid-switch start
        # races the in-flight update for the configuration lock and makes
        # switch-to-configuration fail. Only timers or manual runs start them.
        restartIfChanged = false;
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
      # a timer is safe. On NixOS `systemctl disable` fails (read-only
      # /etc/systemd/system); pause with
      # `systemctl mask --runtime --now lab-update-apply.timer` until reboot,
      # or persistently via the timer's `enable` option below.
      lab-update-apply = {
        description = "Apply available bandit-lab configuration updates";
        wants = ["network-online.target"];
        after = ["network-online.target" "sops-nix.service"];
        # See lab-update-check: never start on unit-file change.
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${labUpdate}/bin/lab-update apply";
          User = "root";
          Environment = ["HOME=/root"];
        };
      };
    };

    timers = {
      lab-update-apply = {
        # Resumed 2026-10-08 at the owner's request: signed fast-forward
        # commits on main are applied hourly (test, health check, switch).
        # enable = false removes the unit again, and activation also stops an
        # already-running timer.
        enable = true;
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
