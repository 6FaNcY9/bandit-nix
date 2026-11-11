#!/usr/bin/env bash
# Restore drill for the public Minecraft world (bandit-craft docs/runbooks/minecraft/PUBLIC.md).
# Owner, on the lab, as root:  sudo bash mc-public-restore-test.sh [snapshot-id]
# Restores the newest (or the given) snapshot of the restic-backups-mc-public job from the peer
# repository into a NEW scratch directory, never over /srv/mc-public/data, checks that it is a usable
# Paper directory and removes the scratch copy. The running world is only read (file counts).
set -euo pipefail
umask 077
snapshot=${1:-latest}
[[ "$snapshot" == latest || "$snapshot" =~ ^[a-fA-F0-9]{8,64}$ ]] || {
  echo 'invalid snapshot ID' >&2
  exit 2
}
staging=/var/backup/restic-staging-mc-public
live=/srv/mc-public/data/paper
# The job's own wrapper (NixOS services.restic.backups.mc-public): repository and password from sops.
restic() { restic-mc-public --no-cache "$@"; }

work=$(mktemp -d /var/tmp/mc-public-restore-XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT

echo "== snapshot"
restic snapshots --path "$staging" --latest 1 --compact
echo "== restoring $snapshot into $work"
restic restore "$snapshot" --path "$staging" --verify --target "$work" >/dev/null
got=$work$staging/paper

fail=0
check() {
  if "${@:2}"; then echo "ok    $1"; else
    echo "FAIL  $1"
    fail=1
  fi
}
regions() { find "$1" -name '*.mca' -size +0 2>/dev/null | wc -l; }
mca_whole() { ! find "$got" -name '*.mca' -size +0 -printf '%s\n' | awk '$1 % 4096 { bad = 1 } END { exit !bad }'; }

check "level.dat is there and unpacks" gzip -t "$got/world/level.dat"
check "the overworld has region files ($(regions "$got/world"))" test "$(regions "$got/world")" -gt 0
check "every region file is whole 4 KiB sectors" mca_whole
check "the whitelist came back" test -s "$got/whitelist.json"
check "server.properties came back" test -s "$got/server.properties"
check "no logs or caches were backed up" test ! -e "$got/logs" -a ! -e "$got/cache"
# The live world grows between the backup and now: the copy may hold fewer region files, never more.
check "region files: restored $(regions "$got") <= live $(regions "$live")" test "$(regions "$got")" -le "$(regions "$live")"

echo "== size: $(du -sh "$got" | cut -f1) restored"
if [ "$fail" = 0 ]; then echo "PASS: restore drill of the public world ($(date -u +%FT%RZ))"; else
  echo "FAILED: see above" >&2
  exit 1
fi
