# Security Hardening Plan

This file tracks the active security posture for the `bandit` laptop. Disk
encryption and boot-chain hardening are intentionally deferred until there is
time to plan recovery and rollback properly. `bandit-lab` hardening is handled
in `hosts/bandit-lab/default.nix` (key-auth-only SSH) and the WAN runbooks.

---

## Current posture — implemented

### System access and local privilege surface
- [x] `nixos/dev.nix`: SSH server is disabled on `bandit`. The machine only
  initiates outbound SSH connections.
- [x] `nixos/dev.nix`: Podman Docker compatibility socket is disabled with
  `dockerCompat = false`.
- [x] `nixos/users.nix`: `vino` is not in the `input`, `storage`, or `podman`
  groups.
- [x] `nixos/network.nix`: DNS-over-TLS is set to `opportunistic` so captive
  portals do not hard-fail.
- [x] `nixos/sops.nix`: `generateKey = false` so a missing SOPS age key fails
  loudly instead of silently generating an unusable key.
- [x] `nixos/core.nix`: `trusted-users` currently includes `root` and `vino`.
  Removing `vino` would require escalating every local rebuild to root; this is
  accepted as a convenience/security trade-off for a single-user laptop.
- [x] `flake.nix`: `nixvim` is kept on its own pinned `nixpkgs`; upstream
  recommends against `inputs.nixpkgs.follows = "nixpkgs"`.

### Home-manager / user environment
- [x] `home/git.nix`: GPG agent default cache TTL is 1 hour, max 4 hours.
- [x] `home/git.nix`: SSH client hardening with `HashKnownHosts`,
  `ServerAliveInterval`, and `ServerAliveCountMax`.
- [x] `home/desktop/hyprland.nix` + `home/desktop/powermenu.nix`: screen locks
  with `hyprlock` before suspend and on idle.
- [x] `home/terminal/fish.nix` and `home/terminal/zsh.nix`: the Cachix auth token
  is read from the sops secret and injected only for the duration of a `cachix`
  call, never exported globally.
- [x] `home/editor/nixvim.nix`: persistent undo, swap, and backups are disabled
  for `*/secrets/*`, `*.age`, and `*.env*` files.
- [x] `home/terminal/kitty.nix`: `copy_on_select = "no"` and
  `scrollback_pager_history_size = 0` so selected text and terminal history are
  not written to disk.

---

## Scoped unfree packages

The shared policy in `lib/repository.nix` allows only the named unfree packages
and the CUDA runtime/toolchain closure needed by Ollama:

```nix
allowUnfreePredicate = pkg: let
  name = lib.getName pkg;
in
  builtins.elem name unfreePackageNames
  || lib.hasPrefix "cuda_" name
  || lib.hasPrefix "libcu" name;
```

Keep this scope exact unless evaluation proves another unfree package is
required; do not return to global `allowUnfree = true`.

---

## SOPS PGP recipient removal

The GPG private key currently lives in `~/.gnupg` on the same machine, so using
it as a SOPS recipient adds decryption attack surface without much recovery
benefit.

Before removing it from `.sops.yaml`, create an encrypted offline USB backup:

```bash
gpg --export-secret-keys --armor 4D8770567A65FE1369E2BCC1611871842A8C1619 > gpg-secret-key.asc
cryptsetup luksFormat /dev/sdX
cryptsetup open /dev/sdX gpg-backup
mkfs.ext4 /dev/mapper/gpg-backup
mount /dev/mapper/gpg-backup /mnt
cp gpg-secret-key.asc /mnt/
umount /mnt && cryptsetup close gpg-backup
shred -u gpg-secret-key.asc
```

After the backup exists:
1. Remove the `pgp:` block from `.sops.yaml`.
2. Add `encrypted_regex: "^.*$"` so all SOPS keys are encrypted by default.
3. Re-encrypt secrets with `sops rotate -i secrets/secrets.yaml secrets/github.yaml`.

---

## Phase 3 — Full-disk encryption with LUKS — DECIDED (2026-07-30)

**Decision: Option B — clean reinstall with LUKS.** Rationale: the system is
fully declarative, so a reinstall costs only data-restore time; it avoids the
in-place data-shift risk, the SSD wear-leveling plaintext caveat, and the
initrd-config sequencing trap.

Implemented as `install-bandit.sh`: one command from the live ISO wipes the
disk, creates a 1 GiB ESP + LUKS2 (argon2id) container, generates
`hosts/bandit/hardware.nix` with the real UUIDs, and hands off to
`install-nixos.sh`. The BTRFS layout changes to match bandit-lab
(`@`, `@home`, `@nix`, `@log`, `@snapshots`); the old `@var` and nested
snapshot subvolumes are gone.

Pre-reinstall checklist for the user (full step-by-step:
`docs/runbooks/bandit-luks-reinstall.md`):
- Full backup of `/home` (encrypted backup medium).
- Export and back up: sops age key (`/var/lib/sops-nix/key.txt`), GPG secret
  key, SSH keys.
- After first boot: commit the generated `hosts/bandit/hardware.nix`, then
  consider TPM2 enrollment (`systemd-cryptenroll`) once Secure Boot lands.

### Option A — In-place re-encryption (rejected)
- Boot from a live USB.
- Make a full backup first.
- Run `cryptsetup reencrypt` on the existing BTRFS partition.
- Keep the laptop on AC; the process can take 1–3 hours.
- Risk is low with a full backup, but not zero.

### Option B — Reinstall with LUKS (chosen)
- Safest and cleanest layout.
- Requires backing up/restoring `/home`, the SOPS age key, SSH keys, and any other local state.

---

## Phase 4 — Pending decision: boot chain hardening

### Option A — GRUB password
- Quick interim improvement.
- Prevents casual GRUB menu/kernel-argument tampering.
- Does not verify the bootloader or kernel.

### Option B — Secure Boot via lanzaboote
- Stronger: verifies bootloader/kernel/initrd.
- Requires key generation and UEFI key enrollment.
- Recovery USB should be ready before enrollment.

Decision needed: quick GRUB password first, or wait and do lanzaboote properly?

---

## Phase 5 — Later hardening

- [ ] Add kernel/sysctl hardening after testing compatibility.
- [ ] Periodically review `vino` in `nix.settings.trusted-users` once local
  rebuild workflows no longer need it.
