# bandit-nix Improvement Plan
> Design spec. Approved 2026-06-22. Approach: Security-First, high risk tolerance.

---

## Overview

Six sequential phases. Each phase is a standalone branch and PR. Phases 1–2 require a maintenance window and recovery USB. Phases 3–6 are safe to execute on the live system.

---

## Phase 1 — LUKS Full-Disk Encryption (reinstall)

**Approach:** Option B clean reinstall (not in-place re-encryption). Cleanest layout, no corruption risk.

### Pre-requisites (must complete before touching disk)

- Encrypted LUKS USB backup of GPG secret key:
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
- `tar` snapshot of `/home/vino` to external drive
- Copy `/var/lib/sops-nix/key.txt` (age key) → same USB
- SSH keys from `~/.ssh/` → same USB
- Recovery USB with NixOS installer

### Target Partition Layout

```
/dev/nvme0n1p1  → EFI (512 MB, FAT32)
/dev/nvme0n1p2  → LUKS2 container (rest of disk)
  └─ BTRFS pool
       ├─ @           → /
       ├─ @home       → /home
       ├─ @nix        → /nix
       └─ @snapshots  → /.snapshots
```

### NixOS Config Changes

**`hosts/bandit/hardware.nix`:**
- Use disk **labels** (not UUIDs) so `hardware.nix` survives reinstalls without edits:
  ```nix
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-label/cryptroot";
    allowDiscards = true;  # SSD TRIM through LUKS
  };
  fileSystems."/" = { device = "/dev/disk/by-label/bandit"; options = ["subvol=@" "noatime" "compress=zstd"]; };
  fileSystems."/home" = { device = "/dev/disk/by-label/bandit"; options = ["subvol=@home" "noatime" "compress=zstd"]; };
  fileSystems."/nix"  = { device = "/dev/disk/by-label/bandit"; options = ["subvol=@nix"  "noatime" "compress=zstd"]; };
  ```
- EFI partition labeled `BOOT` so `fileSystems."/boot"` is also label-stable

**`nixos/boot.nix`:**
- `boot.initrd.availableKernelModules` must include `nvme`, `cryptd`, `aes_x86_64`

### Reinstall Script — `scripts/install-bandit.sh`

Checked into the repo. Run from any NixOS minimal live ISO with network access:

```bash
curl -sL https://raw.githubusercontent.com/6FaNcY9/bandit-nix/main/scripts/install-bandit.sh | bash
```

**Script responsibilities (in order):**

1. Prompt for target disk (e.g. `/dev/nvme0n1`) — safety check: print model + size, require typed confirmation
2. Wipe + repartition with `sgdisk`:
   - p1: 512 MB EFI, type `EF00`, label `BOOT`
   - p2: remainder, type `8309` (LUKS), label `cryptroot`
3. Format EFI: `mkfs.fat -F32 -n BOOT /dev/nvme0n1p1`
4. Create LUKS2 container on p2 (prompts for passphrase): `cryptsetup luksFormat --label cryptroot /dev/nvme0n1p2`
5. Open container: `cryptsetup open /dev/nvme0n1p2 cryptroot`
6. Create BTRFS pool with label `bandit`: `mkfs.btrfs -L bandit /dev/mapper/cryptroot`
7. Create subvolumes: `@`, `@home`, `@nix`, `@snapshots`
8. Mount everything under `/mnt` with correct options
9. Prompt for age key path (e.g. USB at `/run/media/nixos/gpg-backup/key.txt`) → copy to `/mnt/var/lib/sops-nix/key.txt` (creates dir)
10. Install: `nixos-install --flake github:6FaNcY9/bandit-nix#bandit --no-root-passwd`
11. Print post-install checklist (set root password, restore `/home`, restore SSH keys)

**No config edits needed between reinstalls** — labels are stable, flake pulled from GitHub.

---

## Phase 2 — Secure Boot via lanzaboote

**Pre-requisites:** Phase 1 complete (lanzaboote lives inside the LUKS container).

### Steps

1. Generate Secure Boot keys: `sbctl create-keys`
2. Enroll in UEFI: `sbctl enroll-keys --microsoft` (keep Microsoft keys for firmware update compatibility)
3. Switch `nixos/boot.nix`:

```nix
# nixos/boot.nix — replace GRUB block with:
boot.loader.systemd-boot.enable = lib.mkForce false;
boot.lanzaboote = {
  enable = true;
  pkiBundle = "/etc/secureboot";
};
```

4. Add `lanzaboote` flake input to `flake.nix`
5. Sign boot entries: `sbctl sign-all` (lanzaboote handles this on rebuild after initial setup)

### Recovery Path

Recovery USB + NixOS live environment with `sbctl` can re-sign entries if they become corrupted. No need to re-enroll keys.

---

## Phase 3 — CI/CD Hardening

All changes in `.github/workflows/` and `.gitlab-ci.yml`. Safe to do on a feature branch.

### Changes

| Fix | File | Change |
|-----|------|--------|
| Pin Actions to SHA digests | `*.yml` | Replace `@v4` tags with `@<sha>` |
| Fix nightly-build order | `nightly-build.yml` | Commit `flake.lock` only after `flake check` + build pass |
| Fix GitLab Cachix population | `.gitlab-ci.yml` | `nix path-info --recursive ./result \| cachix push ...` |
| Fix GitLab push auth | `.gitlab-ci.yml` | `oauth2:${GITLAB_PUSH_TOKEN}` prefix |
| Move Cachix token | `.gitlab-ci.yml` | Only in push-artifacts jobs, not global setup |
| Tighten GH permissions | `*.yml` | `contents: write` → minimal per-job |

### SOPS validation override

Move `sops.validateSopsFiles = false` from `nixos/default.nix` into a CI-only override. Implementation: add a `nixosConfigurations.bandit-ci` output in `flake.nix` that imports `nixos` + a one-attribute `ci-overrides.nix` that sets `validateSopsFiles = false`. Production `bandit` output is unaffected.

---

## Phase 4 — SOPS / Secrets Cleanup

### 4a — Remove PGP recipient

Pre-req: GPG USB backup from Phase 1 pre-requisites must exist before this step.

1. Edit `.sops.yaml`: remove the `pgp:` block
2. Add `encrypted_regex: "^.*$"` so all keys are encrypted by default
3. Re-encrypt: `sops rotate -i secrets/secrets.yaml secrets/github.yaml`
4. Verify: `sops secrets/secrets.yaml` decrypts successfully with age key only

### 4b — `allowUnfreePredicate`

1. Audit: `grep -r 'allowUnfree\|allowInsecurePredicate' . --include='*.nix'` + check each package's `meta.license`
2. Replace `nixpkgs.config.allowUnfree = true` with:
   ```nix
   nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
     # list populated after audit
   ];
   ```

### 4c — `sops.validateSopsFiles`

Handled in Phase 3 (CI-only override). Remove from `nixos/default.nix` as part of the same PR.

---

## Phase 5 — homelab Deployment (`bandit-lab`)

### Steps

1. **`hosts/bandit-lab/hardware.nix`** — run `nixos-generate-config` on target, copy real UUIDs and kernel modules

2. **`nixos/webhost.nix`** — flesh out:
   - nginx reverse proxy with ACME/Let's Encrypt TLS
   - Firewall: only ports 80, 443, 22 inbound
   - Deploy user with SSH key for push-based deploys

3. **SOPS wiring** — `hosts/bandit-lab/default.nix` imports `nixos/sops.nix`; add lab's age public key to `.sops.yaml`; provision `/var/lib/sops-nix/key.txt` on the target

4. **Home-manager** — skip for bandit-lab (server); shell + editor optional later

### Deployment Command

```bash
nixos-rebuild switch --flake .#bandit-lab --target-host bandit-lab --build-host bandit-lab
```

---

## Phase 6 — Code Quality Cleanup

Small changes, all on one branch.

| Item | File | Fix |
|------|------|-----|
| Commit pending shell changes | `home/aliases.nix`, `home/terminal/zsh.nix` | `nsn` alias + `nsp()` function (already staged) |
| Qt duplication | `home/qt.nix` | Remove `qt5ct.conf` xdg file; keep only `QT_STYLE_OVERRIDE = mkForce "kvantum-dark"` |
| Public IP staleness | `home/desktop/panel.nix` | Check file mtime; if > 10 min old and `ifconfig.me` unreachable, show `?.?.?.x` |
| xfce casing comment | `home/desktop/xfce.nix` | Add one-line comment on duplicate keys |
| `virtio-win` path | `nixos/dev.nix` | Reference `${pkgs.virtio-win}` instead of plain path in comment |

---

## Execution Order

```
Phase 1 (LUKS)  →  Phase 2 (Secure Boot)  →  Phase 3 (CI/CD)
                                           →  Phase 4 (SOPS)
                                           →  Phase 5 (homelab)
                                           →  Phase 6 (cleanup)
```

Phases 3–6 are independent once Phases 1–2 are done. Run in any order or in parallel on separate branches.
