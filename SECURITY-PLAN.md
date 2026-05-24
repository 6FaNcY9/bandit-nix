# Security Hardening Plan

This file tracks the security review work. Low-risk Phase 1/2 changes were started first. Disk encryption and Secure Boot are intentionally left undecided until there is time to plan recovery/rollback properly.

---

## Done now — safe Phase 1/2 hardening

### System access and local privilege surface
- [x] `nixos/core.nix`: removed `vino` from `nix.settings.trusted-users`; only `root` remains trusted by the Nix daemon.
- [x] `nixos/dev.nix`: disabled the SSH server completely. This machine only SSHes out; nobody should SSH in.
- [x] `nixos/dev.nix`: disabled Podman Docker compatibility socket with `dockerCompat = false`.
- [x] `nixos/users.nix`: removed `input`, `storage`, and `podman` groups from `vino`.
- [x] `nixos/network.nix`: changed DNSSEC from `allow-downgrade` to strict validation.
- [x] `nixos/sops.nix`: changed `generateKey` to `false` so a missing SOPS age key fails loudly instead of silently generating an unusable key.
- [x] `nixos/power.nix`: changed lid-close-on-AC from `ignore` to `suspend`.
- [ ] `flake.nix`: keep `nixvim` on its own pinned `nixpkgs`; NixVim upstream recommends against `inputs.nixpkgs.follows` and `flake check` warns when using it.

### Home-manager / user environment
- [x] `home/editor.nix`: removed GitHub Copilot integration.
- [x] `home/terminal.nix`: moved the kitty remote-control socket from `/tmp` to `${XDG_RUNTIME_DIR}`.
- [x] `home/shell.nix`: changed the Cachix token from a globally exported shell variable to a scoped fish wrapper function.
- [x] `home/git.nix`: reduced GPG agent max cache TTL from 24 hours to 4 hours.
- [x] `home/git.nix`: added explicit SSH client hardening with `HashKnownHosts`, `ServerAliveInterval`, and `ServerAliveCountMax`.
- [x] `home/git.nix`: changed `git wip` from `commit -am 'wip'` to `commit -m 'wip'` so it no longer stages every modified tracked file automatically.
- [x] `home/desktop/i3.nix`: added `xss-lock` so the screen locks before suspend.

---

## Deferred Phase 1/2 items

These are still good ideas, but should not be rushed.

### `allowUnfreePredicate`
Current config uses:

```nix
nixpkgs.config.allowUnfree = true;
```

Do not replace this blindly. First audit which unfree packages are actually needed, then create a precise `allowUnfreePredicate`. An incomplete predicate can make `nixos-rebuild` fail.

### Strict DNS-over-TLS
`DNSOverTLS = "yes"` gives stronger privacy than opportunistic mode, but port 853 is blocked on some hotel/café/airport networks. For now, keep `DNSOverTLS = "opportunistic"` unless broken DNS on restrictive networks is acceptable.

### SOPS validation in CI
`nixos/default.nix` still has:

```nix
sops.validateSopsFiles = false;
```

This should be moved out of production config, but only together with CI changes that pass the override in CI. Do this as one atomic change so CI does not break.

### Flake input branches
- Keep `home-manager/master` for now because this system tracks `nixos-unstable`. Switching to a release branch while `nixpkgs` remains unstable can introduce module compatibility problems.
- Keep `nixvim` on its own pinned `nixpkgs`. NixVim upstream recommends against `inputs.nixpkgs.follows = "nixpkgs"` because NixVim is tested against its pinned revision.

### SOPS PGP recipient removal
The GPG private key currently lives in `~/.gnupg` on the same machine, so using it as a SOPS recipient adds decryption attack surface without much recovery benefit.

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

### CI/CD cleanup
Still pending:
- Reorder `.github/workflows/nightly-build.yml` so `flake.lock` is committed only after checks/builds pass.
- Fix `.gitlab-ci.yml` Cachix population: use `nix path-info --recursive ./result | cachix push ...`.
- Fix `.gitlab-ci.yml` `update-flake` auth prefix: use `oauth2:${GITLAB_PUSH_TOKEN}` for PATs.
- Move `cachix authtoken` out of global CI setup and into only jobs that push artifacts.
- Pin GitHub Actions and CI Docker images to immutable digests/SHAs.
- Tighten GitHub workflow `permissions` blocks.
- Make the VM smoke test actually check for a login prompt.

---

## Phase 3 — Pending decision: Full-disk encryption with LUKS

### Option A — In-place re-encryption
- Boot from a live USB.
- Make a full backup first.
- Run `cryptsetup reencrypt` on the existing BTRFS partition.
- Keep the laptop on AC; the process can take 1–3 hours.
- Risk is low with a full backup, but not zero.

### Option B — Reinstall with LUKS
- Safest and cleanest layout.
- Requires backing up/restoring `/home`, the SOPS age key, SSH keys, and any other local state.

Decision needed: do you want in-place re-encryption or a clean reinstall?

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
- [ ] Disable Neovim persistent undo for secrets paths like `*/secrets/*`, `*.age`, and `*.env`.
- [ ] Review CopyQ clipboard history and kitty `copy_on_select` behavior.
- [ ] Set kitty `scrollback_pager_history_size = 0` or rely on LUKS/tmpfs for `/tmp`.
