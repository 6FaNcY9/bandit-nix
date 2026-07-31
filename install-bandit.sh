#!/usr/bin/env bash
set -euo pipefail

# bandit laptop reinstall: wipes the internal disk, sets up GPT + LUKS2,
# generates hosts/bandit/hardware.nix with the real UUIDs, then hands off
# to install-nixos.sh with the opened LUKS mapper as the BTRFS target.
#
# One-liner from the NixOS live ISO:
#   sudo ./install-bandit.sh --disk /dev/nvme0n1 --age-key /run/media/nixos/USB/key.txt

disk=""
age_key=""
mode="all"
luks_name="cryptroot"
esp_size="1GiB"
skip_confirm=0
skip_flake_check=0

usage() {
  cat <<'EOF'
Usage:
  sudo ./install-bandit.sh --disk DEV [options]

LUKS reinstall installer for the bandit laptop. Wipes the WHOLE disk:
partition 1 = EFI system partition, partition 2 = LUKS2 container with
BTRFS subvolumes (@, @home, @nix, @log, @snapshots) inside.

Required:
  --disk DEV              Whole disk to erase, e.g. /dev/nvme0n1.
                         All existing data and operating systems are destroyed.

Options:
  --age-key PATH          sops-nix age private key copied to
                         /mnt/var/lib/sops-nix/key.txt.
  --mode MODE             all, prepare, mount, install. Default: all.
                         mount/install reuse the existing LUKS container
                         (passphrase is asked again to open it).
  --luks-name NAME        Device mapper name. Default: cryptroot.
  --esp-size SIZE         EFI partition size. Default: 1GiB.
  --skip-flake-check      Do not evaluate the flake before disk changes.
  --yes-i-understand      Skip destructive confirmation prompt.
  -h, --help              Show this help.

Resume examples:
  # Rebooted after partitioning; open LUKS, mount, then install:
  sudo ./install-bandit.sh --disk /dev/nvme0n1 --mode mount
  sudo ./install-bandit.sh --disk /dev/nvme0n1 --mode install

After the first successful boot, commit the generated
hosts/bandit/hardware.nix — it contains the UUIDs of the new disk.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk)
      disk="${2:-}"
      shift 2
      ;;
    --age-key)
      age_key="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --luks-name)
      luks_name="${2:-}"
      shift 2
      ;;
    --esp-size)
      esp_size="${2:-}"
      shift 2
      ;;
    --skip-flake-check)
      skip_flake_check=1
      shift
      ;;
    --yes-i-understand)
      skip_confirm=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "$(id -u)" == "0" ]] || die "run as root"
[[ -n "$disk" ]] || die "--disk is required"
[[ -b "$disk" ]] || die "disk is not a block device: $disk"

case "$mode" in
  all|prepare|mount|install) ;;
  *) die "--mode must be one of: all, prepare, mount, install" ;;
esac

if [[ -n "$age_key" && ! -f "$age_key" ]]; then
  die "age key does not exist: $age_key"
fi

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Partition naming: /dev/nvme0n1p1 vs /dev/sda1
case "$disk" in
  *nvme*|*mmcblk*|*loop*) part_prefix="p" ;;
  *) part_prefix="" ;;
esac
esp_dev="${disk}${part_prefix}1"
luks_part="${disk}${part_prefix}2"
mapper="/dev/mapper/$luks_name"

need_cmd sgdisk
need_cmd cryptsetup
need_cmd blkid

info "Disk: $disk (ESP: $esp_dev, LUKS: $luks_part)"
info "LUKS mapper: $mapper"
info "Mode: $mode"

if [[ "$mode" == "all" || "$mode" == "prepare" ]]; then
  if [[ "$skip_confirm" != "1" ]]; then
    printf '\nThis will ERASE ALL DATA on %s — the whole disk, including any other OS.\n' "$disk"
    printf 'Type ERASE %s to continue: ' "$disk"
    read -r answer
    [[ "$answer" == "ERASE $disk" ]] || die "confirmation did not match; aborting"
  fi

  info "Partitioning $disk"
  sgdisk --zap-all "$disk"
  sgdisk --new=1:1MiB:+"$esp_size" --typecode=1:EF00 --change-name=1:ESP "$disk"
  # 8309 = Linux LUKS partition type GUID
  sgdisk --new=2:0:0 --typecode=2:8309 --change-name=2:"$luks_name" "$disk"
  sleep 2 # let the kernel notice the new partition table

  info "Formatting EFI partition"
  need_cmd mkfs.vfat
  mkfs.vfat -F 32 -n ESP "$esp_dev"

  info "Setting up LUKS2 container (choose a strong passphrase)"
  cryptsetup luksFormat --type luks2 --pbkdf argon2id "$luks_part"
  cryptsetup open "$luks_part" "$luks_name"
fi

if [[ "$mode" == "mount" || "$mode" == "install" ]]; then
  if [[ ! -b "$mapper" ]]; then
    info "Opening existing LUKS container"
    cryptsetup open "$luks_part" "$luks_name"
  fi
fi

# Generate hardware.nix with the real UUIDs of this disk. Written before
# install-nixos.sh runs so its flake check evaluates the new file.
luks_uuid="$(cryptsetup luksUUID "$luks_part")"
esp_uuid="$(blkid -s UUID -o value "$esp_dev")"
info "Generating hosts/bandit/hardware.nix (LUKS $luks_uuid, ESP $esp_uuid)"

# NOTE: no Nix string interpolation in this template — the heredoc is
# shell-expanded, so only the two UUIDs may use $variables.
cat > "$repo/hosts/bandit/hardware.nix" <<EOF
# Generated by install-bandit.sh during the LUKS reinstall.
# Commit this file after the first successful boot — it replaces the
# pre-encryption hardware.nix (plain BTRFS, different UUIDs and layout).
{modulesPath, ...}: let
  rootDev = "$mapper";
  btrfsDefaults = ["noatime" "compress=zstd" "space_cache=v2" "discard=async"];
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
      ];
      luks.devices.$luks_name = {
        device = "/dev/disk/by-uuid/$luks_uuid";
        # TRIM through LUKS for the NVMe; pairs with discard=async mounts.
        allowDiscards = true;
      };
    };
    kernelModules = ["kvm-amd"];
  };

  fileSystems = {
    "/" = {
      device = rootDev;
      fsType = "btrfs";
      options = ["subvol=@"] ++ btrfsDefaults;
    };
    "/home" = {
      device = rootDev;
      fsType = "btrfs";
      options = ["subvol=@home"] ++ btrfsDefaults;
    };
    "/nix" = {
      device = rootDev;
      fsType = "btrfs";
      options = ["subvol=@nix"] ++ btrfsDefaults;
    };
    "/var/log" = {
      device = rootDev;
      fsType = "btrfs";
      options = ["subvol=@log"] ++ btrfsDefaults;
      neededForBoot = true;
    };
    "/.snapshots" = {
      device = rootDev;
      fsType = "btrfs";
      options = ["subvol=@snapshots"] ++ btrfsDefaults;
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/$esp_uuid";
      fsType = "vfat";
      options = ["fmask=0077" "dmask=0077"];
    };
  };

  swapDevices = [];
}
EOF

extra_args=()
if [[ "$skip_flake_check" == "1" ]]; then
  extra_args+=(--skip-flake-check)
fi
key_args=()
if [[ -n "$age_key" ]]; then
  key_args=(--age-key "$age_key")
fi

# install-nixos.sh formats BTRFS on the mapper, creates the subvolumes,
# mounts everything, copies the age key, and runs nixos-install.
exec "${BASH}" "$repo/install-nixos.sh" \
  --host bandit \
  --root-dev "$mapper" \
  --boot-dev "$esp_dev" \
  --btrfs-label bandit \
  --mode "$mode" \
  --yes-i-understand \
  "${key_args[@]}" \
  "${extra_args[@]}"
