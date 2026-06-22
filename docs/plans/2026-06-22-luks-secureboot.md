# LUKS + Secure Boot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace unencrypted BTRFS install with LUKS2-encrypted disk and sign the boot chain with lanzaboote (Secure Boot).

**Architecture:** All NixOS config changes (hardware.nix, default.nix, flake.nix) are committed to main before the reinstall. The install script reads the flake directly from GitHub — no USB needed for config. After reinstall, lanzaboote signs boot entries; Secure Boot keys are enrolled once in UEFI firmware.

**Tech Stack:** NixOS flake, alejandra, lanzaboote, sbctl, cryptsetup, sgdisk, btrfs-progs, shellcheck.

## Global Constraints

- alejandra 2-space indent, no trailing whitespace
- `nix flake check --no-update-lock-file` must pass after every task
- `system.stateVersion = "25.11"` — never change
- Never modify `*.age`, `*.key`, `secrets.yaml`, `.sops.yaml`
- Lint: `nix run nixpkgs#alejandra -- --check .` + `nix run nixpkgs#deadnix -- --fail .` + `nix run nixpkgs#statix -- check .`

---

### Task 1: Update hardware.nix — disk labels + LUKS config

**Files:**
- Modify: `hosts/bandit/hardware.nix`

**Why:** Current file uses UUIDs (`by-uuid/0629aaee...`, `by-uuid/CC4A-AF6B`). After reinstall these change. Switching to partition labels (`by-partlabel/`) means `hardware.nix` never needs editing after a reinstall — the install script sets matching labels.

BTRFS mounts use `/dev/mapper/cryptroot` (the opened LUKS device name, stable because it's derived from the key name in `luks.devices`, not from any hardware identifier).

- [ ] **Step 1: Replace hardware.nix**

  Write the full replacement (no UUID references remain):

  ```nix
  {modulesPath, ...}: let
    rootDev = "/dev/mapper/cryptroot";
    btrfsDefaults = ["compress=zstd" "noatime" "discard=async"];
    swapOpts = ["noatime" "discard=async"];
    btrfsSubvol = subvol: extraOpts: {
      device = rootDev;
      fsType = "btrfs";
      options = ["subvol=${subvol}"] ++ extraOpts;
    };
  in {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    boot = {
      initrd = {
        availableKernelModules = [
          "nvme"
          "xhci_pci"
          "thunderbolt"
          "usb_storage"
          "uas"
          "sd_mod"
          "cryptd"
          "aes_x86_64"
        ];
        kernelModules = [];
        luks.devices."cryptroot" = {
          device = "/dev/disk/by-partlabel/cryptroot";
          allowDiscards = true;
        };
      };
      kernelModules = ["kvm-amd"];
      extraModulePackages = [];
    };

    fileSystems = {
      "/" = btrfsSubvol "@" btrfsDefaults;
      "/home" = btrfsSubvol "@home" btrfsDefaults;
      "/nix" = btrfsSubvol "@nix" btrfsDefaults;
      "/var" = btrfsSubvol "@var" btrfsDefaults;
      "/swap" = btrfsSubvol "@swap" swapOpts;
      "/.snapshots" = btrfsSubvol "@/.snapshots" btrfsDefaults;
      "/home/.snapshots" = btrfsSubvol "@home/.snapshots" btrfsDefaults;
      "/boot" = {
        device = "/dev/disk/by-partlabel/BOOT";
        fsType = "vfat";
        options = ["fmask=0077" "dmask=0077"];
      };
    };

    swapDevices = [];
  }
  ```

- [ ] **Step 2: Run linters**

  ```bash
  nix run nixpkgs#alejandra -- --check hosts/bandit/hardware.nix
  nix run nixpkgs#deadnix -- --fail hosts/bandit/hardware.nix
  nix run nixpkgs#statix -- check hosts/bandit/hardware.nix
  ```

  Expected: no output (all pass).

- [ ] **Step 3: Dry-run build**

  ```bash
  nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
    --dry-run --no-update-lock-file 2>&1 | tail -5
  ```

  Expected: "these derivations will be built" or "0 derivations" — no eval error.

- [ ] **Step 4: Commit**

  ```bash
  git add hosts/bandit/hardware.nix
  git commit -m "feat(hardware): switch to partition labels + add LUKS2 initrd config"
  ```

---

### Task 2: Replace GRUB with lanzaboote in hosts/bandit/default.nix

**Files:**
- Modify: `hosts/bandit/default.nix`

**Why:** lanzaboote wraps systemd-boot and signs boot entries. It cannot coexist with GRUB. The `lib.mkForce false` on `systemd-boot.enable` is required because lanzaboote internally enables systemd-boot and then immediately disables it — without mkForce, the two conflict.

`sbctl` is added as a system package so it's available after first boot to enroll Secure Boot keys.

- [ ] **Step 1: Replace the boot.loader block in default.nix**

  Current file is:
  ```nix
  {lib, ...}: {
    imports = [
      ./hardware.nix
      ../../nixos/tor.nix
    ];

    networking.hostName = "bandit";
    system.stateVersion = "25.11";

    # ── Bootloader (GRUB + EFI) ───────────────────────────────────────────────
    boot.loader = {
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        useOSProber = false;
        configurationLimit = 10;
        splashImage = lib.mkForce null;
      };
      efi.canTouchEfiVariables = true;
    };

    # Framework 13 AMD 7040: s2idle is the only working suspend mode.
    boot.kernelParams = ["mem_sleep_default=s2idle"];
  }
  ```

  Replace the entire `boot.loader` block (keep everything else):

  ```nix
  {lib, pkgs, ...}: {
    imports = [
      ./hardware.nix
      ../../nixos/tor.nix
    ];

    networking.hostName = "bandit";
    system.stateVersion = "25.11";

    boot.loader = {
      systemd-boot.enable = lib.mkForce false;
      efi.canTouchEfiVariables = true;
    };

    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
    };

    environment.systemPackages = [pkgs.sbctl];

    # Framework 13 AMD 7040: s2idle is the only working suspend mode.
    boot.kernelParams = ["mem_sleep_default=s2idle"];
  }
  ```

- [ ] **Step 2: Run linters**

  ```bash
  nix run nixpkgs#alejandra -- --check hosts/bandit/default.nix
  nix run nixpkgs#deadnix -- --fail hosts/bandit/default.nix
  nix run nixpkgs#statix -- check hosts/bandit/default.nix
  ```

  Expected: no output.

- [ ] **Step 3: Dry-run build — will FAIL until Task 3 adds the lanzaboote module**

  ```bash
  nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
    --dry-run --no-update-lock-file 2>&1 | tail -10
  ```

  Expected: eval error — `boot.lanzaboote` undefined. This is correct at this step. Proceed.

- [ ] **Step 4: Commit**

  ```bash
  git add hosts/bandit/default.nix
  git commit -m "feat(boot): replace GRUB with lanzaboote, add sbctl"
  ```

---

### Task 3: Add lanzaboote flake input + NixOS module

**Files:**
- Modify: `flake.nix`

**Why:** `boot.lanzaboote` is not a built-in NixOS option — it comes from the lanzaboote flake's NixOS module. Without adding the input and wiring the module, Task 2's config causes an eval error.

- [ ] **Step 1: Check latest lanzaboote release tag**

  ```bash
  curl -s https://api.github.com/repos/nix-community/lanzaboote/releases/latest \
    | grep '"tag_name"'
  ```

  Note the tag (e.g. `v0.4.1`). Use it in the next step.

- [ ] **Step 2: Add lanzaboote input to flake.nix**

  In the `inputs` block (after `nixos-hardware`), add:

  ```nix
  lanzaboote = {
    url = "github:nix-community/lanzaboote/<TAG-FROM-STEP-1>";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  ```

- [ ] **Step 3: Thread lanzaboote into outputs**

  In the `outputs` function signature, add `lanzaboote` to the destructured inputs:

  ```nix
  outputs = {
    nixpkgs,
    home-manager,
    sops-nix,
    stylix,
    nixos-hardware,
    lanzaboote,
    ...
  } @ inputs:
  ```

- [ ] **Step 4: Add lanzaboote NixOS module to bandit configuration**

  In `nixosConfigurations.bandit.modules`, add `lanzaboote.nixosModules.lanzaboote` after `nixos-hardware.nixosModules.framework-13-7040-amd`:

  ```nix
  modules = [
    {nixpkgs.hostPlatform = "x86_64-linux";}
    stylix.nixosModules.stylix
    nixos-hardware.nixosModules.framework-13-7040-amd
    lanzaboote.nixosModules.lanzaboote
    sops-nix.nixosModules.sops
    ./hosts/bandit
    ./nixos
    home-manager.nixosModules.home-manager
    {home-manager = hmBase;}
  ];
  ```

- [ ] **Step 5: Update flake.lock**

  ```bash
  nix flake lock --update-input lanzaboote
  ```

  Expected: `flake.lock` updated with lanzaboote entry.

- [ ] **Step 6: Dry-run build — must pass now**

  ```bash
  nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
    --dry-run --no-update-lock-file 2>&1 | tail -5
  ```

  Expected: no eval error.

- [ ] **Step 7: Run full lint suite**

  ```bash
  nix flake check --no-update-lock-file
  nix run nixpkgs#alejandra -- --check .
  nix run nixpkgs#deadnix -- --fail .
  nix run nixpkgs#statix -- check .
  ```

  Expected: all pass (deadnix and statix may warn about unused `lanzaboote` binding if not used directly — acceptable).

- [ ] **Step 8: Commit**

  ```bash
  git add flake.nix flake.lock
  git commit -m "feat(flake): add lanzaboote input and wire NixOS module for bandit"
  ```

---

### Task 4: Write scripts/install-bandit.sh

**Files:**
- Create: `scripts/install-bandit.sh`

**Why:** The reinstall script automates disk setup so any future reinstall is a single command from the NixOS live ISO. No UUID editing required afterward — partition labels are stable.

**Assumptions when run from live ISO:**
- Running as root (`sudo -i` or already root)
- Network is up (needed to pull flake from GitHub)
- Target disk is the Framework 13's NVMe: `/dev/nvme0n1` (script confirms with user)
- Age key (SOPS) is on a USB, typically at `/run/media/nixos/*/key.txt`

- [ ] **Step 1: Create scripts/install-bandit.sh**

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  # ── helpers ──────────────────────────────────────────────────────────────────
  die()  { echo "ERROR: $*" >&2; exit 1; }
  info() { echo "==> $*"; }

  [[ $EUID -eq 0 ]] || die "run as root (sudo -i)"

  # ── 1. target disk ───────────────────────────────────────────────────────────
  info "Available disks:"
  lsblk -dno NAME,SIZE,MODEL | grep -v loop

  read -r -p "Target disk (e.g. /dev/nvme0n1): " DISK
  [[ -b "$DISK" ]] || die "$DISK is not a block device"

  info "Selected: $DISK"
  lsblk -dno NAME,SIZE,MODEL "$DISK"
  read -r -p "Type 'yes' to wipe and repartition $DISK: " CONFIRM
  [[ "$CONFIRM" == "yes" ]] || die "aborted"

  EFI="${DISK}p1"
  CRYPTPART="${DISK}p2"

  # ── 2. partition ─────────────────────────────────────────────────────────────
  info "Partitioning $DISK..."
  sgdisk --zap-all "$DISK"
  sgdisk \
    -n1:0:+512M -t1:ef00 -c1:BOOT \
    -n2:0:0     -t2:8309 -c2:cryptroot \
    "$DISK"
  partprobe "$DISK"
  sleep 1

  # ── 3. EFI ───────────────────────────────────────────────────────────────────
  info "Formatting EFI partition..."
  mkfs.fat -F32 -n BOOT "$EFI"

  # ── 4. LUKS ──────────────────────────────────────────────────────────────────
  info "Creating LUKS2 container on $CRYPTPART..."
  cryptsetup luksFormat --type luks2 "$CRYPTPART"
  cryptsetup open "$CRYPTPART" cryptroot

  # ── 5. BTRFS + subvolumes ────────────────────────────────────────────────────
  info "Creating BTRFS pool..."
  mkfs.btrfs -L bandit /dev/mapper/cryptroot

  info "Creating subvolumes..."
  mount /dev/mapper/cryptroot /mnt
  for subvol in @ @home @nix @var @swap "@/.snapshots" "@home/.snapshots"; do
    btrfs subvolume create "/mnt/$subvol"
  done
  umount /mnt

  # ── 6. mount for nixos-install ───────────────────────────────────────────────
  info "Mounting filesystems..."
  BOPTS="compress=zstd,noatime,discard=async"
  mount -o "subvol=@,$BOPTS"               /dev/mapper/cryptroot /mnt
  mkdir -p /mnt/{boot,home,nix,var,swap,.snapshots,home/.snapshots}
  mount -o "subvol=@home,$BOPTS"           /dev/mapper/cryptroot /mnt/home
  mount -o "subvol=@nix,$BOPTS"            /dev/mapper/cryptroot /mnt/nix
  mount -o "subvol=@var,$BOPTS"            /dev/mapper/cryptroot /mnt/var
  mount -o "subvol=@swap,noatime,discard=async" /dev/mapper/cryptroot /mnt/swap
  mount -o "subvol=@/.snapshots,$BOPTS"    /dev/mapper/cryptroot /mnt/.snapshots
  mount -o "subvol=@home/.snapshots,$BOPTS" /dev/mapper/cryptroot /mnt/home/.snapshots
  mount "$EFI" /mnt/boot

  # ── 7. age key ───────────────────────────────────────────────────────────────
  info "Looking for SOPS age key..."
  AGE_KEY=""
  for candidate in /run/media/nixos/*/key.txt /run/media/nixos/*/sops-nix-key.txt; do
    if [[ -f "$candidate" ]]; then
      AGE_KEY="$candidate"
      break
    fi
  done

  if [[ -z "$AGE_KEY" ]]; then
    read -r -p "Age key not found. Enter full path to key.txt (or press Enter to skip): " AGE_KEY
  fi

  if [[ -n "$AGE_KEY" && -f "$AGE_KEY" ]]; then
    info "Copying age key from $AGE_KEY..."
    mkdir -p /mnt/var/lib/sops-nix
    install -m 0400 "$AGE_KEY" /mnt/var/lib/sops-nix/key.txt
  else
    info "WARNING: No age key installed. Secrets will not decrypt on first boot."
    info "         Manually copy the key to /var/lib/sops-nix/key.txt after install."
  fi

  # ── 8. install ───────────────────────────────────────────────────────────────
  info "Running nixos-install..."
  nixos-install \
    --flake "github:6FaNcY9/bandit-nix#bandit" \
    --no-root-passwd \
    --root /mnt

  # ── 9. post-install checklist ────────────────────────────────────────────────
  info "Install complete. Post-install checklist:"
  cat <<'CHECKLIST'

  ┌─ AFTER FIRST BOOT ──────────────────────────────────────────────────────┐
  │                                                                          │
  │  1. Set root password:    passwd root                                    │
  │  2. Restore /home:        tar -xf /path/to/home-backup.tar -C /home     │
  │  3. Restore SSH keys:     cp /run/media/.../ssh/* ~/.ssh/                │
  │  4. Generate SB keys:     sudo sbctl create-keys                        │
  │  5. Sign boot entries:    sudo sbctl sign-all                           │
  │  6. Enroll keys in UEFI:  sudo sbctl enroll-keys --microsoft            │
  │  7. Enable Secure Boot in UEFI firmware settings, reboot                │
  │                                                                          │
  └──────────────────────────────────────────────────────────────────────────┘

  CHECKLIST

  info "Unmounting..."
  umount -R /mnt
  cryptsetup close cryptroot
  info "Done. Remove the live USB and reboot."
  ```

- [ ] **Step 2: Make executable**

  ```bash
  chmod +x scripts/install-bandit.sh
  ```

- [ ] **Step 3: Run shellcheck**

  ```bash
  nix run nixpkgs#shellcheck -- scripts/install-bandit.sh
  ```

  Expected: no warnings or errors.

- [ ] **Step 4: Commit**

  ```bash
  git add scripts/install-bandit.sh
  git commit -m "feat(scripts): add LUKS+BTRFS reinstall script for bandit"
  ```

---

### Task 5: Final validation

**Files:** None (read-only checks)

- [ ] **Step 1: Full lint suite**

  ```bash
  nix flake check --no-update-lock-file
  nix run nixpkgs#alejandra -- --check .
  nix run nixpkgs#deadnix -- --fail .
  nix run nixpkgs#statix -- check .
  nix run nixpkgs#shellcheck -- scripts/install-bandit.sh
  ```

  All must pass.

- [ ] **Step 2: Dry-run build**

  ```bash
  nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
    --dry-run --no-update-lock-file
  ```

  Expected: completes without error.

- [ ] **Step 3: Commit pending shell changes (from git status)**

  The `home/aliases.nix` + `home/terminal/zsh.nix` changes are already staged:

  ```bash
  git add home/aliases.nix home/terminal/zsh.nix
  git commit -m "feat(shell): rename nsp alias to nsn, add nsp() multi-package function"
  ```

---

## Execution Order

Tasks 1–3 can be done in one session — they're all config changes. Task 4 (install script) is independent of Tasks 1–3 and can be done before or after.

```
Task 1 (hardware.nix) → Task 2 (default.nix) → Task 3 (flake.nix)
Task 4 (install script) — independent
Task 5 (validate) — after Tasks 1–4
```

## Physical Execution (after all tasks committed and pushed)

From NixOS live ISO with network:

```bash
curl -sL https://raw.githubusercontent.com/6FaNcY9/bandit-nix/main/scripts/install-bandit.sh | bash
```

Then follow the post-install checklist printed by the script.
