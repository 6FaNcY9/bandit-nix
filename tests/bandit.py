start_all()

# System initialisation
bandit.wait_for_unit("multi-user.target")
bandit.succeed("test \"$(systemctl --failed --no-legend | wc -l)\" -eq 0")

# Network services
bandit.wait_for_unit("NetworkManager.service")
bandit.succeed("systemctl is-active NetworkManager")
bandit.wait_for_unit("systemd-resolved.service")

# User configuration
bandit.succeed("id vino")
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
