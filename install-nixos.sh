#!/usr/bin/env bash
set -euo pipefail

host=""
flake_ref=""
root_dev=""
boot_dev=""
age_key=""
btrfs_label="nixos"
mode="all"
skip_confirm=0
skip_flake_check=0

usage() {
  cat <<'EOF'
Usage:
  sudo ./install-nixos.sh --host HOST --root-dev DEV --boot-dev DEV [options]

Generic NixOS live-ISO installer for flake-based hosts.

Required:
  --host HOST             Flake host to install, for example bandit-lab.
  --root-dev PATH         Root partition to format or mount as BTRFS.
  --boot-dev PATH         EFI system partition to mount at /boot.

Options:
  --flake-ref REF         Flake reference. Default: this repo path.
                         Install target becomes REF#HOST.
  --age-key PATH          sops-nix age private key copied to
                         /mnt/var/lib/sops-nix/key.txt.
  --btrfs-label LABEL     BTRFS filesystem label. Default: nixos.
  --mode MODE             all, prepare, mount, install. Default: all.
                         all     = flake check, format, mount, copy key, install
                         prepare = flake check, format, mount, copy key
                         mount   = mount existing subvolumes, copy key
                         install = run nixos-install against mounted /mnt
  --skip-flake-check      Do not evaluate the flake before disk changes.
  --yes-i-understand      Skip destructive confirmation prompt.
  -h, --help              Show this help.

Resume examples:
  # Network died during nixos-install, but /mnt is still mounted:
  sudo ./install-nixos.sh --host bandit-lab --root-dev /dev/nvme0n1p5 \
    --boot-dev /dev/nvme0n1p1 --age-key /tmp/key.txt --mode install

  # Rebooted after formatting; mount existing subvolumes, then install:
  sudo ./install-nixos.sh --host bandit-lab --root-dev /dev/nvme0n1p5 \
    --boot-dev /dev/nvme0n1p1 --age-key /tmp/key.txt --mode mount
  sudo ./install-nixos.sh --host bandit-lab --root-dev /dev/nvme0n1p5 \
    --boot-dev /dev/nvme0n1p1 --age-key /tmp/key.txt --mode install
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

repo_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      host="${2:-}"
      shift 2
      ;;
    --flake-ref)
      flake_ref="${2:-}"
      shift 2
      ;;
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
    --btrfs-label)
      btrfs_label="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
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
[[ -n "$host" ]] || die "--host is required"
[[ -n "$root_dev" ]] || die "--root-dev is required"
[[ -n "$boot_dev" ]] || die "--boot-dev is required"
[[ -b "$root_dev" ]] || die "root device is not a block device: $root_dev"
[[ -b "$boot_dev" ]] || die "boot device is not a block device: $boot_dev"
[[ "$root_dev" != "$boot_dev" ]] || die "--root-dev and --boot-dev must differ"

case "$mode" in
  all|prepare|mount|install) ;;
  *) die "--mode must be one of: all, prepare, mount, install" ;;
esac

[[ -n "$flake_ref" ]] || flake_ref="$(repo_dir)"
target="$flake_ref#$host"

if [[ -n "$age_key" && ! -f "$age_key" ]]; then
  die "age key does not exist: $age_key"
fi

need_cmd findmnt
need_cmd mount
need_cmd nix
need_cmd nixos-install

if [[ "$mode" == "all" || "$mode" == "prepare" || "$mode" == "mount" ]]; then
  need_cmd btrfs
fi

info "Host: $host"
info "Flake target: $target"
info "Root partition: $root_dev"
info "EFI partition: $boot_dev"
[[ -n "$age_key" ]] && info "SOPS age key: $age_key"
info "Mode: $mode"

if [[ "$mode" == "all" || "$mode" == "prepare" ]]; then
  if findmnt "$root_dev" >/dev/null 2>&1; then
    die "$root_dev is mounted; boot the live ISO or unmount it before formatting"
  fi
  if mountpoint -q /mnt; then
    die "/mnt is mounted; unmount it or use --mode install if it is already prepared"
  fi

  if [[ "$skip_confirm" != "1" ]]; then
    printf '\nThis will erase all data on %s and install NixOS %s.\n' "$root_dev" "$host"
    printf 'Type ERASE %s to continue: ' "$root_dev"
    read -r answer
    [[ "$answer" == "ERASE $root_dev" ]] || die "confirmation did not match; aborting"
  fi

  if [[ "$skip_flake_check" != "1" ]]; then
    info "Checking flake before touching disks"
    nix --extra-experimental-features 'nix-command flakes' flake check --no-update-lock-file "$flake_ref"
  fi

  info "Formatting BTRFS root partition"
  mkfs.btrfs -f -L "$btrfs_label" "$root_dev"

  info "Creating BTRFS subvolumes"
  mount "$root_dev" /mnt
  for subvol in @ @home @nix @log @snapshots; do
    btrfs subvolume create "/mnt/$subvol"
  done
  umount /mnt
fi

if [[ "$mode" == "all" || "$mode" == "prepare" || "$mode" == "mount" ]]; then
  if mountpoint -q /mnt; then
    die "/mnt is already mounted; unmount it before mounting target filesystems"
  fi

  info "Mounting target filesystems"
  mount -o subvol=@,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt
  mkdir -p /mnt/{boot,home,nix,var/log,.snapshots}
  mount -o subvol=@home,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt/home
  mount -o subvol=@nix,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt/nix
  mount -o subvol=@log,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt/var/log
  mount -o subvol=@snapshots,noatime,compress=zstd,space_cache=v2,discard=async "$root_dev" /mnt/.snapshots
  mount "$boot_dev" /mnt/boot

  if [[ -n "$age_key" ]]; then
    info "Installing sops-nix age key"
    install -m 0700 -d /mnt/var/lib/sops-nix
    install -m 0400 "$age_key" /mnt/var/lib/sops-nix/key.txt
  else
    info "No age key passed; secrets may fail until /var/lib/sops-nix/key.txt exists"
  fi
fi

if [[ "$mode" == "all" || "$mode" == "install" ]]; then
  mountpoint -q /mnt || die "/mnt is not mounted; run --mode prepare or --mode mount first"
  mountpoint -q /mnt/boot || die "/mnt/boot is not mounted"

  if [[ -n "$age_key" && ! -f /mnt/var/lib/sops-nix/key.txt ]]; then
    info "Installing sops-nix age key"
    install -m 0700 -d /mnt/var/lib/sops-nix
    install -m 0400 "$age_key" /mnt/var/lib/sops-nix/key.txt
  fi

  info "Checking network name resolution"
  if ! getent hosts cache.nixos.org >/dev/null 2>&1; then
    info "Warning: cache.nixos.org did not resolve; nixos-install may fail until networking is fixed"
  fi

  info "Installing NixOS"
  if ! nixos-install --flake "$target" --no-root-passwd; then
    cat >&2 <<EOF

error: nixos-install failed.

If this was a network failure, fix networking and rerun:
  sudo $0 --host $host --root-dev $root_dev --boot-dev $boot_dev --mode install${age_key:+ --age-key $age_key}${flake_ref:+ --flake-ref $flake_ref}

Do not rerun the default/all mode unless you intentionally want to reformat.
EOF
    exit 1
  fi
fi

info "Done."
if [[ "$mode" == "prepare" || "$mode" == "mount" ]]; then
  info "Target is mounted at /mnt. Run again with --mode install when ready."
else
  info "Reboot into $host when ready."
fi
