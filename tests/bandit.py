start_all()

# System initialisation
bandit.wait_for_unit("multi-user.target")
# `systemctl --failed` returns 0 even when units are listed, so assert that
# no units are in the failed state by inverting `--quiet` (which exits 0
# only when there *are* failed units).
bandit.fail("systemctl --failed --quiet")

# Network services
bandit.wait_for_unit("NetworkManager.service")
bandit.succeed("systemctl is-active NetworkManager")
bandit.wait_for_unit("systemd-resolved.service")

# User configuration
bandit.succeed("id vino")
# Use `id -nG` and word-grep so a real failure of `id` isn't masked by the
# exit code of `grep` in a pipeline.
bandit.succeed("id -nG vino | grep -wq wheel")
bandit.succeed("id -nG vino | grep -wq networkmanager")

# Shell and user-facing tools
bandit.succeed("which fish")
bandit.succeed("su -l vino -c 'fish --version'")
bandit.succeed("su -l vino -c 'nvim --version'")
bandit.succeed("su -l vino -c 'git --version'")

# Nix settings
bandit.succeed("grep 'flakes' /etc/nix/nix.conf")
bandit.succeed("grep 'auto-optimise-store' /etc/nix/nix.conf")

# Audio and hardware services
# pipewire runs as a systemd --user unit on NixOS, so query it via the
# user manager files rather than the system manager.
bandit.succeed("test -e /etc/systemd/user/pipewire.socket")
bandit.succeed("systemctl is-enabled bluetooth.service")
