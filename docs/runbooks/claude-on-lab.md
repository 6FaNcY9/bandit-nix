# Claude Code on bandit-lab (account `claude`, bugbounty mode)

Claude Code reaches the lab as `claude` (hosts/bandit-lab/services/bugbounty/claude.nix):
SSH key only, from the owner's phone and laptop over Tailscale, no sudo, no docker.

## Connect

- Key per device, made there and never copied: `ssh-keygen -t ed25519 -f ~/.ssh/id_claude_lab -C claude@<device>`.
  Its `.pub` line goes into `keys` in claude.nix (phone: done).
- Home Manager adds `Host claude-lab` (modules/user/ssh.nix). `bandit-lab` stays the owner's alias.
- Test: `ssh claude-lab id`.

## Without asking

- Logs and states: `journalctl -u <unit>`, `systemctl status <unit>`, `bugbounty`.
- Builds (as `claude`, not trusted): from a copy of the repo,
  `nix build .#nixosConfigurations.bandit-lab.config.system.build.toplevel --no-link`.
- What a mode switch would change: `systemctl start bugbounty-dry`, then
  `journalctl -u bugbounty-dry -o cat -n 80`.
- Tools in bugbounty mode, only against targets in a program's scope; notes in `~vino/bugbounty`
  belong to the owner, so Claude keeps its own under `~/bugbounty`.

## Only with the owner's OK (owner types it, with the sudo password)

- `sudo bugbounty on` / `sudo bugbounty off`
- `nixos-rebuild switch`, deploys (signed push to main, `lab-apply`)
- stopping or restarting services, `dry-activate` of a candidate that is not deployed
  (it runs the candidate's own code as root)

Hand these over as one short line each, labelled with the host.

## Modes and rollback

- `on` and `off` use `switch-to-configuration test`: the boot loader is never touched, so a
  reboot always comes back in normal mode.
- In bugbounty mode `lab-update-apply.timer` is masked; after `off` it resumes. A `lab-apply`
  from the laptop returns the lab to normal mode.
- Bad deploy: `sudo nixos-rebuild switch --rollback`, or pick the previous generation in the
  boot menu.
