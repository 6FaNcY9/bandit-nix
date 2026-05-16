# System initialisation
bandit.wait_for_unit("multi-user.target")
bandit.succeed("systemctl --failed --no-pager")

# Network services
bandit.wait_for_unit("NetworkManager.service")
bandit.succeed("systemctl is-active NetworkManager")
bandit.wait_for_unit("systemd-resolved.service")

# User configuration
bandit.succeed("id vino")
bandit.succeed("groups vino | grep -q wheel")
bandit.succeed("groups vino | grep -q networkmanager")

# Shell and user-facing tools
bandit.succeed("which fish")
bandit.succeed("su -l vino -c 'fish --version'")
bandit.succeed("su -l vino -c 'nvim --version'")
bandit.succeed("su -l vino -c 'git --version'")

# Nix settings
bandit.succeed("grep 'flakes' /etc/nix/nix.conf")
bandit.succeed("grep 'auto-optimise-store' /etc/nix/nix.conf")

# Audio and hardware services
bandit.succeed("systemctl is-enabled pipewire.socket")
bandit.succeed("systemctl is-enabled bluetooth.service")
