#!/usr/bin/env bash
set -euo pipefail

host="bandit-lab"
root_dev="/dev/nvme0n1p5"
boot_dev="/dev/nvme0n1p1"
age_key=""
skip_confirm=0

usage() {
  cat <<'EOF'
Usage:
  sudo ./install-bandit-lab.sh --age-key /path/to/key.txt [options]

Installs the bandit-lab NixOS host from a live NixOS session.

Options:
  --root-dev PATH        Root partition to format as BTRFS.
                         Default: /dev/nvme0n1p5
  --boot-dev PATH        Existing EFI system partition to mount at /boot.
                         Default: /dev/nvme0n1p1
  --age-key PATH         Existing sops-nix age private key to install at
                         /mnt/var/lib/sops-nix/key.txt.
  --yes-i-understand     Skip the destructive confirmation prompt.
  -h, --help             Show this help.

Example:
  git clone https://github.com/6FaNcY9/bandit-nix.git
  cd bandit-nix
  sudo ./install-bandit-lab.sh --age-key /run/media/nixos/USB/key.txt

This script formats only the root partition. It does not format the EFI
partition, but it mounts the partition passed with --boot-dev.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-dev)
      root_dev="${2:-}"
      shift 2
      ;;
    --boot-dev)
      boot_dev="${2:-}"
      shift 2
      ;;
    --age-key)
      age_key="${2:-}"
      shift 2
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

[[ "$(id -u)" == "0" ]] || die "run as root, for example: sudo $0 --age-key /path/to/key.txt"
[[ -b "$root_dev" ]] || die "root device is not a block device: $root_dev"
[[ -b "$boot_dev" ]] || die "boot device is not a block device: $boot_dev"
[[ -n "$age_key" ]] || die "--age-key is required; the configured user password is encrypted with sops-nix"
[[ -f "$age_key" ]] || die "age key does not exist: $age_key"
mountpoint -q /mnt && die "/mnt is already mounted; unmount it before running this installer"

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info "Repository: $repo"
info "Host: $host"
info "Root partition to format: $root_dev"
info "EFI partition to mount: $boot_dev"
info "SOPS age key: $age_key"

if [[ "$skip_confirm" != "1" ]]; then
  printf '\nThis will erase all data on %s and install NixOS %s.\n' "$root_dev" "$host"
  printf 'Type ERASE %s to continue: ' "$root_dev"
  read -r answer
  [[ "$answer" == "ERASE $root_dev" ]] || die "confirmation did not match; aborting"
fi

info "Checking flake before touching disks"
nix --extra-experimental-features 'nix-command flakes' flake check --no-update-lock-file "$repo"

info "Formatting BTRFS root partition"
mkfs.btrfs -f -L bandit-lab "$root_dev"

info "Creating BTRFS subvolumes"
mount "$root_dev" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@snapshots
umount /mnt

info "Mounting target filesystems"
mount -o subvol=@,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt
mkdir -p /mnt/{boot,home,nix,var/log,.snapshots}
mount -o subvol=@home,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt/home
mount -o subvol=@nix,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt/nix
mount -o subvol=@log,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt/var/log
mount -o subvol=@snapshots,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt/.snapshots
mount "$boot_dev" /mnt/boot

info "Installing sops-nix age key"
install -m 0700 -d /mnt/var/lib/sops-nix
install -m 0400 "$age_key" /mnt/var/lib/sops-nix/key.txt

info "Installing NixOS"
nixos-install --flake "$repo#$host" --no-root-passwd

info "Install complete. Reboot into $host when ready."
