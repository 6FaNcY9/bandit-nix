# Restore the phone (pong) after a reset

The phone's Nix side lives in a root chroot at `/data/nix-root` (design:
`docs/specs/2026-11-16-phone-nix-host-design.md`). Everything in it can be rebuilt from this
repo plus one secret, the age key in Bitwarden. Termux keeps a small rescue kit that works
without the chroot: `pkt`, `boot-backup`, `root-doctor`, `ssh`, `git`, Claude Code.

## Before you need it

- The Bitwarden 2FA recovery code is kept **off this phone** (paper or the laptop).
- The Bitwarden secure note `pong age key` holds the content of
  `/home/vino/.config/sops/age/keys.txt` from the chroot. Without it the phone cannot
  decrypt `secrets/pong.yaml`, and the keys in it have to be made again.
- Google contacts sync is on (Settings → Google → Contacts sync).
- Boot backups: see `/sdcard/Download/root-backups/` and the copies on bandit-lab.

## Restore

1. Root comes back first (kernel, KSU manager, modules); that is outside this runbook.
2. Install Termux and its plugins from the `termux/*` GitHub releases only (same signing
   key; not F-Droid or Play). Open Termux once, then grant it root in the KSU manager
   (full capabilities, not a custom profile).
3. In Termux:

   ```sh
   pkg install -y curl
   curl -fsSLO https://raw.githubusercontent.com/6FaNcY9/bandit-nix/main/hosts/pong/bootstrap/pong-bootstrap
   sh pong-bootstrap
   ```

   It installs the rescue kit, clones this repo to `~/src/bandit-nix`, installs Nix into
   `/data/nix-root`, asks for the Bitwarden login (email, master password, 2FA, then the
   master password once more to unlock) and writes the age key into the chroot, runs
   `pong-switch`, links `pkt` and the two root scripts for Termux, and adds the Termux hook
   to `~/.zshrc`. It ends with `ssh pc ok`, `pkt ok`, `root-doctor ok`. After a failure, fix
   the cause and run it again: done steps are skipped.
4. By hand, because they are logins and not in the repo:
   - Claude Code in Termux (rescue build): the launcher from
     `ferrumclaudepilgrim/claude-code-android`, then `claude` and log in.
   - Claude Code in the chroot: `curl -fsSL https://claude.ai/install.sh | bash` inside a
     Nix shell, then log in. It runs because `pong-nix-root` links the FHS loader.
   - MCP servers and their tokens in `~/.claude.json`; `~/.claude/CLAUDE.md` (kept off the
     public repo) from the owner's copy.
   - `gh auth login` if the token from `secrets/pong.yaml` is not enough.
5. Add the Termux apps to the HMA hiding template again (HMA has no launcher icon:
   `su -c 'am start -n org.frknkrc44.hma_oss/.ui.activity.MainActivity'`; it saves the
   template only after you leave its screen with Back).
6. `sh ~/src/bandit-nix/hosts/pong/bootstrap/pong-hide-check` → `OK hidden`.

## After every reboot

Open Termux and check that a new session lands in the Nix zsh (no
`pong-nix failed, Termux shell` line). If it fails, the session stays in Termux and the
rescue kit works; `touch ~/.no-pong-nix` turns the hook off until the cause is fixed.

## Drill

Builds a second chroot and checks it, without touching the real one or Bitwarden:

```sh
PONG_NIX_ROOT=/data/nix-root-drill \
PONG_AGE_KEY_FROM=/data/nix-root/home/vino/.config/sops/age/keys.txt \
  sh hosts/pong/bootstrap/pong-bootstrap --no-termux-hook
su -c 'rm -rf /data/nix-root-drill'   # check the path first
sh hosts/pong/bootstrap/pong-hide-check
```
