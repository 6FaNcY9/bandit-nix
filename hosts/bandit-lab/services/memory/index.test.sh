#!/usr/bin/env bash
# Laptop test for index.sh against temp dirs: bash index.test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { bash "$here/index.sh"; }
v=$t/vino f=$t/firma
mkdir -p "$v/projects" "$f/projects"

# vino: a canary that must never reach firma's lagebild, plus a mirrored note.
printf -- '---\ntitle: secret\nstatus: active\nrepo: ~/src/secret main\n---\n- [ ] CANARY-7f3 do the private thing (owner)\n' > "$v/projects/secret.md"
printf -- '- [ ] mirrored step (owner)\n' > "$v/projects/bandit-craft.md"
# firma: late human step, doing before open, claude steps, a long cell with | and [[links]].
printf -- '---\ntitle: aiia\nrepo: "~/src/aiia-create main"\n---\n## Tasks\n- [ ] Draft reply (claude)\n- [ ] Answer the 5 delete questions (vino, Albert, 2000-01-02)\n- [/] Claude-side check (Claude Code, 2000-01-01)\n- [x] old done (owner, 2000-01-01)\n- [/] Ship the [[form]] | fix %s (owner)\n' "$(printf 'x%.0s' {1..100})" > "$f/projects/aiia.md"
printf -- '---\nstatus: done\n---\n- [ ] DONE-HIDDEN (owner)\n' > "$f/projects/finished.md"
printf -- '---\nstatus: paused\n---\n- [ ] PAUSED-STEP (owner)\n' > "$f/projects/resting.md"
# The mirrored copy in firma: listed in firma's own view, skipped in vino's.
printf -- '- [ ] mirrored step (owner)\n' > "$f/projects/bandit-craft.md"

# A symlink into the vino store must not be read; CRLF notes parse like LF ones.
ln -s "$v/projects/secret.md" "$f/projects/link.md"
printf -- '---\r\nstatus: done\r\n---\r\n- [ ] CRLF-HIDDEN (owner)\r\n' > "$f/projects/crlf.md"

export MEMORY_INDEX_DST=$f MEMORY_INDEX_SOURCES="firma=$f" MEMORY_INDEX_SKIP=
run > /dev/null || fail "firma run failed"
out=$(cat "$f/lagebild.md")
case $out in *CRLF-HIDDEN*|*"| link |"*) fail "symlink or CRLF note listed" ;; esac
[[ $out != *CANARY* && $out != *secret* ]] || fail "vino content in firma's lagebild"
[[ $out == *"| bandit-craft | firma |"* ]] || fail "firma's own mirrored copy missing from its view"

MEMORY_INDEX_DST=$t/elsewhere run 2> /dev/null && fail "DST not the first source accepted"
MEMORY_INDEX_SOURCES="vino=$v firma=$f" run 2> /dev/null && fail "firma DST with vino first accepted"
[[ $(cat "$f/lagebild.md") != *CANARY* ]] || fail "refused run still wrote"

export MEMORY_INDEX_DST=$v MEMORY_INDEX_SOURCES="vino=$v firma=$f" MEMORY_INDEX_SKIP="projects/bandit-craft.md projects/x.md"
run > /dev/null || fail "vino run failed"
out=$(cat "$v/lagebild.md")
[[ $out == "---"$'\n'"title: Lagebild"$'\n'"type: index"$'\n'"permalink: main/lagebild"$'\n'"---"* ]] || fail "front matter"
[ "$(grep -c '^| bandit-craft |' "$v/lagebild.md")" = 1 ] || fail "SKIP not honoured (bandit-craft twice)"
grep -q '^| bandit-craft | vino |' "$v/lagebild.md" || fail "vino's own bandit-craft missing"
grep -q '^> Project notes: one `## Stand`' "$v/lagebild.md" || fail "format rule line missing"
[[ $out != *DONE-HIDDEN* && $out != *"| finished |"* ]] || fail "done project shown"
grep -q '^| resting | firma | paused | 1 | 0 | 0 | PAUSED-STEP |' "$v/lagebild.md" || fail "paused row"
[[ $(sed -n '/^## Waiting/,/^## Projects/p' "$v/lagebild.md") != *PAUSED-STEP* ]] || fail "paused project waits for a human"

row=$(grep '^| aiia |' "$v/lagebild.md")
IFS='|' read -r _ p s st o d l h c r ch _ <<< "$row"
[ "$p $s $st $o $d $l" = " aiia   firma   active   2   2   2 " ] || fail "aiia counts: $row"
# [/] before [ ]: the human step is the doing one, Claude's is the doing "Claude Code" one.
[[ $h == " Ship the form / fix x"* && $h == *"… " ]] || fail "human cell not doing-first or not sanitised: $h"
[ "$c" = " Claude-side check " ] || fail "claude cell: $c"
[ "$r" = " ~/src/aiia-create main " ] || fail "repo: $r"
[[ $ch =~ ^\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ $ ]] || fail "changed: $ch"
# Sorted by late desc: aiia (2 late) first.
[ "$(sed -n '/^|---/{n;p;q}' "$v/lagebild.md")" = "$row" ] || fail "aiia not first"

# Late steps first in "Waiting"; LATE survives the cut.
first=$(grep -m1 '^1\. ' "$v/lagebild.md")
[[ $first == "1. aiia (firma): Ship the form / fix x"*"… (owner)" ]] || fail "waiting line: $first"
printf -- '- [ ] Late human (Albert, 2000-01-05)\n' > "$f/projects/zz.md"
run > /dev/null
[[ $(grep -m1 '^1\. ' "$v/lagebild.md") == "1. zz (firma): Late human (Albert) LATE 2000-01-05" ]] || fail "late step not first"
printf -- '- [ ] %s (Albert, 2000-01-05)\n' "$(printf 'y%.0s' {1..120})" > "$f/projects/zz.md"
run > /dev/null
grep -q '^1\. zz (firma): y*… (Albert) LATE 2000-01-05$' "$v/lagebild.md" || fail "LATE cut off a long line"

# Every line at most 80 characters, no stray table breakers.
while IFS= read -r line; do
  if [[ $line == "|"* ]]; then
    IFS='|' read -ra cells <<< "${line:1}"
    for cell in "${cells[@]}"; do [ "${#cell}" -le 82 ] || fail "cell too long: $cell"; done
    [ "${#cells[@]}" = 10 ] || fail "cell count ${#cells[@]}: $line"
  elif [[ $line != ">"* ]]; then
    [ "${#line}" -le 80 ] || fail "line too long: $line"
  fi
done < "$v/lagebild.md"
[[ $(cat "$v/lagebild.md") != *"[["* ]] || fail "wiki link left"

# .wartet.md: lagebild's Waiting rows uncut, each at most 280 characters.
w=$v/.wartet.md
[ -f "$w" ] || fail ".wartet.md missing"
[ "$(head -1 "$w")" = "## Waiting for a human" ] || fail "wartet heading"
[ "$(grep -c '^[0-9]*\. ' "$w")" = "$(sed -n '/^## Waiting/,/^## Projects/p' "$v/lagebild.md" | grep -c '^[0-9]*\. ')" ] || fail "wartet row count"
grep -qx "1\. zz (firma): $(printf 'y%.0s' {1..120}) (Albert) LATE 2000-01-05" "$w" || fail "wartet row cut"
grep -q '^[0-9]*\. aiia (firma): Ship the form / fix x\{100\} (owner)$' "$w" || fail "aiia row cut in wartet"
printf -- '- [ ] %s (Albert, 2000-01-05)\n' "$(printf 'y%.0s' {1..300})" > "$f/projects/zz.md"
run > /dev/null
first=$(grep -m1 '^1\. ' "$w")
[[ $first == *"… (Albert) LATE 2000-01-05" && ${#first} -le 280 ]] || fail "long wartet row: ${#first}"
while IFS= read -r line; do [ "${#line}" -le 280 ] || fail "wartet line too long"; done < "$w"
[[ $(cat "$f/.wartet.md") != *CANARY* ]] || fail "vino content in firma's wartet"
e=$t/empty
mkdir -p "$e/projects"
printf -- '- [ ] x (claude)\n' > "$e/projects/x.md"
MEMORY_INDEX_DST=$e MEMORY_INDEX_SOURCES="empty=$e" MEMORY_INDEX_SKIP= run > /dev/null || fail "empty run failed"
[ "$(cat "$e/.wartet.md")" = "## Waiting for a human"$'\n'"Nothing." ] || fail "empty wartet: $(cat "$e/.wartet.md")"

# A second run with nothing changed rewrites nothing.
touch -d '2000-01-01' "$v/lagebild.md" "$v/.wartet.md"
out=$(run)
[ -z "$out" ] || fail "second run wrote: $out"
[ "$(stat -c %Y "$v/lagebild.md")" = "$(date -d 2000-01-01 +%s)" ] || fail "unchanged lagebild touched"
[ "$(stat -c %Y "$v/.wartet.md")" = "$(date -d 2000-01-01 +%s)" ] || fail "unchanged wartet touched"
[ -z "$(find "$t" -name '.lagebild.*')" ] || fail "temp file left behind"
echo "index.test.sh: ok"
