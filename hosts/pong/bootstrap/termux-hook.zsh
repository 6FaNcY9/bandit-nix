# Sourced at the end of the Termux ~/.zshrc: a new interactive Termux session
# goes straight into the pong Nix shell. Skipped for Claude Code's own shells,
# inside the chroot, and while ~/.no-pong-nix exists (plain Termux, rescue kit).
# If entering fails (no root, slot B, no chroot), this stays a Termux shell.
if [[ -o interactive && -t 0 && -z $CLAUDECODE && -z $PONG_NIX && ! -e ~/.no-pong-nix ]]; then
  ${0:A:h}/pong-nix-enter
  if [[ $? -eq 2 ]]; then
    print -P "%F{yellow}pong-nix failed, Termux shell (touch ~/.no-pong-nix to skip)%f"
  else
    exit
  fi
fi
