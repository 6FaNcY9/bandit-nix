# One-way mirror: copies the notes in MEMORY_NOTES (space-separated paths) from
# vino's store into the firma store, so staff can read them but their edits are
# reverted on the next run. Never writes to the source, never deletes in firma.
# Files are written straight into firma's data dir: Basic Memory's file watcher
# indexes them, as it does the summariser's session notes.
set -u
src=${MEMORY_SRC:-/srv/containers/memory/data/basic-memory}
dst=${MEMORY_DST:-/srv/containers/memory-firma/data/basic-memory}
banner='> Nur lesen: Kopie aus vinos Speicher. Änderungen hier werden alle 10 Minuten überschrieben.'
status=0

for note in ${MEMORY_NOTES:-}; do
  if ! [[ $note =~ ^[A-Za-z0-9._/-]+\.md$ ]] || [[ $note == *..* || $note == /* ]]; then
    echo "bad note path $note" >&2
    status=1
    continue
  fi
  if [ ! -f "$src/$note" ]; then
    echo "skip $note: not in source"
    continue
  fi
  mkdir -p "$(dirname "$dst/$note")"
  tmp=$(mktemp "$dst/.mirror.XXXXXX") || { status=1; continue; }
  # Banner right after the YAML front matter, or at the top without one.
  if ! awk -v b="$banner" '
      NR == 1 && $0 == "---" { fm = 1; print; next }
      NR == 1 { print b; print ""; done = 1 }
      fm && !done && $0 == "---" { print; print b; print ""; done = 1; next }
      { print }
      END { if (!done) { print ""; print b } }
    ' "$src/$note" > "$tmp"; then
    rm -f "$tmp"
    status=1
    continue
  fi
  if cmp -s "$tmp" "$dst/$note"; then
    rm -f "$tmp"
  else
    chmod 0644 "$tmp"
    mv -f "$tmp" "$dst/$note"
    echo "mirrored $note"
  fi
done
exit "$status"
