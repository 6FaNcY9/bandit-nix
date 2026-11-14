#!/usr/bin/env bash
# Laptop test for mirror.sh against temp dirs: bash mirror.test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export MEMORY_SRC=$t/src MEMORY_DST=$t/dst MEMORY_NOTES="projects/fm.md projects/plain.md projects/gone.md"
banner='> Nur lesen: Kopie aus vinos Speicher. Änderungen hier werden alle 10 Minuten überschrieben.'
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { bash "$here/mirror.sh"; }

mkdir -p "$MEMORY_SRC/projects" "$MEMORY_DST"
printf -- '---\ntitle: fm\npermalink: main/projects/fm\n---\n\n# FM\nbody\n' > "$MEMORY_SRC/projects/fm.md"
printf '# Plain\nbody\n' > "$MEMORY_SRC/projects/plain.md"
cp -r "$MEMORY_SRC" "$t/src-before"

out=$(run) || fail "first run exited non-zero"
[[ $out == *"skip projects/gone.md"* ]] || fail "missing source not logged as skipped"
[ ! -e "$MEMORY_DST/projects/gone.md" ] || fail "missing source created a copy"

expected=$(printf -- '---\ntitle: fm\npermalink: main/projects/fm\n---\n%s\n\n\n# FM\nbody' "$banner")
[ "$(cat "$MEMORY_DST/projects/fm.md")" = "$expected" ] || fail "banner not after front matter"
expected=$(printf '%s\n\n# Plain\nbody' "$banner")
[ "$(cat "$MEMORY_DST/projects/plain.md")" = "$expected" ] || fail "banner not at top"

# Unchanged content is not rewritten.
touch -d '2000-01-01' "$MEMORY_DST/projects/fm.md"
out=$(run)
[[ $out != *mirrored* ]] || fail "second run rewrote: $out"
[ "$(stat -c %Y "$MEMORY_DST/projects/fm.md")" = "$(date -d 2000-01-01 +%s)" ] || fail "unchanged copy touched"

# A staff edit to a copy is overwritten; other firma notes stay.
echo "staff edit" >> "$MEMORY_DST/projects/plain.md"
echo "firma own" > "$MEMORY_DST/projects/own.md"
out=$(run)
[[ $out == *"mirrored projects/plain.md"* ]] || fail "modified copy not overwritten"
[ "$(cat "$MEMORY_DST/projects/plain.md")" = "$expected" ] || fail "overwrite content wrong"
[ -f "$MEMORY_DST/projects/own.md" ] || fail "firma note deleted"

diff -r "$t/src-before" "$MEMORY_SRC" > /dev/null || fail "source changed"
[ -z "$(find "$MEMORY_DST" -name '.mirror.*')" ] || fail "temp file left behind"
MEMORY_NOTES="../etc/passwd.md" run > /dev/null 2>&1 && fail "bad path accepted"
echo "mirror.test.sh: ok"
