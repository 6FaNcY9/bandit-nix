#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${BASH}" "$repo/install-nixos.sh" \
  --host bandit-lab \
  --boot-mount /efi \
  --btrfs-label bandit-lab \
  "$@"
