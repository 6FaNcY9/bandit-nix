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
- [x] `flake.nix`: keep `nixvim` on its own pinned `nixpkgs`; NixVim upstream recommends against `inputs.nixpkgs.follows` and `flake check` warns when using it.

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

### Scoped unfree packages
Completed through the shared policy in `lib/repository.nix`. NixOS and the
standalone Home Manager package set both allow only the named packages and the
CUDA runtime/toolchain closure needed by Ollama. Keep this scope exact unless
evaluation proves another unfree package is required; do not return to global
`allowUnfree = true`.

```nix
allowUnfreePredicate = pkg: let
  name = lib.getName pkg;
in
  builtins.elem name unfreePackageNames
  || lib.hasPrefix "cuda_" name
  || lib.hasPrefix "libcu" name;
```

### Strict DNS-over-TLS
`DNSOverTLS = "yes"` gives stronger privacy than opportunistic mode, but port 853 is blocked on some hotel/café/airport networks. For now, keep `DNSOverTLS = "opportunistic"` unless broken DNS on restrictive networks is acceptable.

### SOPS validation in CI
Production SOPS validation is no longer disabled in `nixos/sops.nix`.
The CI-only override lives in `nixos/ci-overrides.nix`:

```nix
sops.validateSopsFiles = false;
```

Keep this override scoped to the `bandit-ci` output so normal host
evaluation still validates encrypted SOPS files.

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
Completed:
- [x] GitHub workflow permissions are limited to each job's required scope.
- [x] Nix formatting is a read-only check; GitHub Actions no longer commits to the default branch.
- [x] The VM smoke test checks for a login prompt or completed startup.
- [x] GitHub and GitLab use `nix flake check` as the pinned formatter/linter/installer test entry point.
- [x] CI evaluates all public NixOS outputs and the standalone Home Manager output.
- [x] GitLab installs and authenticates Cachix only in the manual cache-push job.
- [x] Cachix population pushes the full recursive result closure.
- [x] The duplicate formatter workflow and GitLab branch-mutating auto-fix job were removed.
- [x] Vulnix is pinned by `flake.lock`, publishes JSON reports, and fails on findings not present in `ci/vulnix-whitelist.toml`.

Keep GitHub Actions and CI Docker images pinned to immutable digests/SHAs. Any
vulnerability exception must name the affected CVE, explain why it is accepted,
and have a short expiry date.

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
- [x] Disable Neovim persistent undo, swap, and backups for secrets paths like `*/secrets/*`, `*.age`, and `*.env`.
- [x] Keep CopyQ available for explicit clipboard use, but disable kitty's automatic `copy_on_select` behavior.
- [x] Set kitty `scrollback_pager_history_size = 0` so terminal scrollback is not written to disk.
