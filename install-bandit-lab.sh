#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$repo/install-nixos.sh" \
  --host bandit-lab \
  --root-dev /dev/nvme0n1p5 \
  --boot-dev /dev/nvme0n1p1 \
  --boot-mount /efi \
  --btrfs-label bandit-lab \
  "$@"
