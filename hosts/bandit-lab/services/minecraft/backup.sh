# minecraft-backup: consistent full backup of the Minecraft data directory.
#
# snapshot (saves flushed + frozen, rsync) -> tar.zst -> sha256 -> listing test
# -> retention. Archives live in $MC_BACKUPS/auto, the newest MC_KEEP are kept.
# Only a verified archive counts: on any failure the partial files are removed
# and the unit fails (so it alerts) while older archives stay untouched.
set -euo pipefail

backups=${MC_BACKUPS:-/srv/containers/minecraft/backups}/auto
keep=${MC_KEEP:-14}
work=$backups/.work
stamp=$(date +%Y%m%d-%H%M%S)
archive=$backups/minecraft-$stamp.tar.zst

mkdir -p "$backups"
chmod 0750 "$backups"
cleanup() {
  rm -rf "$work"
  rm -f -- "$archive.part"
}
trap cleanup EXIT
cleanup

minecraft-snapshot "$work/data"

tar --use-compress-program='zstd -T2 -3' -cf "$archive.part" -C "$work" data
mv "$archive.part" "$archive"
(cd "$backups" && sha256sum "$(basename "$archive")" >"$archive.sha256")
# Listing the archive proves it is readable end to end; the checksum file is
# for the off-host copy and for the pre-restore check.
tar --use-compress-program=unzstd -tf "$archive" >/dev/null
(cd "$backups" && sha256sum --check "$(basename "$archive").sha256")

# Retention: the newest $keep archives (and their checksums) survive.
mapfile -t old < <(find "$backups" -maxdepth 1 -name 'minecraft-*.tar.zst' | sort -r | tail -n +"$((keep + 1))")
for f in "${old[@]}"; do
  rm -f -- "$f" "$f.sha256"
done
echo "backup complete: $archive"
