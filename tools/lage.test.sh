#!/usr/bin/env bash
# Test for tools/lage.py with a fake HOME, fixture sessions and transcripts, a fixed clock.
# Run: tools/lage.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export TZ=UTC COLUMNS=46 LINES=27 LAGE_NOW=2026-11-15T14:12:20Z PYTHONDONTWRITEBYTECODE=1
s1=aaaaaaaa-1
n=0
fresh() { # a new empty HOME for the next test
  n=$((n + 1)); export HOME=$t/h$n
  mkdir -p "$HOME/.claude/sessions" "$HOME/.claude/projects/p" "$HOME/w" "$HOME/empty"
}
lage() { python3 "$here/lage.py" "$@"; }
session() { # session <pid> <sid> <name> <start cwd> [startedAt ms]: session file and an empty transcript
  echo '{"pid":'"$1"',"sessionId":"'"$2"'","name":"'"$3"'","cwd":"'"$4"'","startedAt":'"${5:-1794700000000}"',"status":"busy"}' \
    >"$HOME/.claude/sessions/$1.json"
  : >"$HOME/.claude/projects/p/$2.jsonl"
}
entry() { echo "$2" >>"$HOME/.claude/projects/p/$1.jsonl"; } # entry <sid> <json>
assistant() { # assistant <time> <stop_reason json> <content json>
  echo '{"type":"assistant","timestamp":"2026-11-15T'"$1"'Z","message":{"stop_reason":'"$2"',"content":'"$3"'}}'
}
tool() { # tool <name> <input json>: the newest entry is a tool call, 20 s old
  fresh; session $$ $s1 src-a "$HOME/w"
  entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"'"$1"'","input":'"$2"'}]')"
  out=$(lage --dir "$HOME/w" --once)
}

board() { mkdir -p "$HOME/.local/state/lage"; cat >"$HOME/.local/state/lage/$s1.md"; } # board: stdin becomes the board of $s1
bfile() { echo "$HOME/.local/state/lage/$s1.md"; }
owner() { # owner <time>: an owner prompt at that time today
  entry $s1 '{"type":"user","timestamp":"2026-11-15T'"$1"'Z","origin":{"kind":"human"},"message":{"content":"los"}}'
}
widest() { python3 -c 'import sys; print(max(len(l) for l in sys.stdin.read().split("\n")))'; }

# test_tool_use
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"prüft die Webseite"}}]')"
entry $s1 '{"type":"mode"}'                                  # no timestamp: skipped
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"JETZT ▶ prüft die Webseite"* && $out == *"Bash · seit 20 s"* && $out == *"Stand 14:12"* ]]
first=$(head -n 1 <<<"$out")
[[ $first == "LAGE  w"*"Stand 14:12" && ${#first} -eq 46 ]]    # right-aligned to the window width

# test_partial_line: garbage and a half-written line change nothing
before=$out
echo garbage >>"$HOME/.claude/projects/p/$s1.jsonl"
echo '{"type":"assistant", garbage' >>"$HOME/.claude/projects/p/$s1.jsonl"
printf '{"type":"assistant","timest' >>"$HOME/.claude/projects/p/$s1.jsonl"
[[ $(lage --dir "$HOME/w" --once) == "$before" ]]

# test_other_tools
tool Bash '{}';                                          [[ $out == *"JETZT ▶ Bash"* ]]
tool Read '{"file_path":"/a/b/notes.md"}';               [[ $out == *"JETZT ▶ liest notes.md"* && $out == *"Read · seit 20 s"* ]]
tool Edit '{"file_path":"/a/b/x.nix"}';                  [[ $out == *"JETZT ▶ ändert x.nix"* ]]
tool Write '{"file_path":"/a/y.py"}';                    [[ $out == *"JETZT ▶ ändert y.py"* ]]
tool MultiEdit '{"file_path":"/a/z.sh"}';                [[ $out == *"JETZT ▶ ändert z.sh"* ]]
tool NotebookEdit '{"notebook_path":"/a/n.ipynb"}';      [[ $out == *"JETZT ▶ ändert n.ipynb"* ]]
tool Grep '{"pattern":"foo.*bar"}';                      [[ $out == *"JETZT ▶ sucht foo.*bar"* ]]
tool Glob '{"pattern":"**/*.nix"}';                      [[ $out == *"JETZT ▶ sucht **/*.nix"* ]]
tool Agent '{"description":"Ports"}';                    [[ $out == *"JETZT ▶ Helfer: Ports"* ]]
tool Task '{"description":"Ports"}';                     [[ $out == *"JETZT ▶ Helfer: Ports"* ]]
tool WebFetch '{"url":"x"}';                             [[ $out == *"JETZT ▶ WebFetch"* && $out == *"WebFetch · seit 20 s"* ]]
tool Read '{}';                                          [[ $out == *"JETZT ▶ Read"* ]]   # nothing to name: the tool name
# the last tool_use item of the entry counts
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/a/first"}},{"type":"text","text":"t"},{"type":"tool_use","name":"Read","input":{"file_path":"/a/second"}}]')"
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"liest second"* && $out != *first* ]]

# test_end_turn
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"end_turn"' '[{"type":"text","text":"fertig"}]')"
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"JETZT ▶ wartet auf dich"* && $out == *"seit 20 s"* ]]

# test_helpers: a helper without "finished" and a recently written log keeps the session busy
sub=$HOME/.claude/projects/p/$s1/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-a1.meta.json"; echo '{}' >"$sub/agent-a1.jsonl"
touch -d 2026-11-15T14:10:00Z "$sub/agent-a1.jsonl"
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"Helfer arbeiten (1)"* && $out == *"seit 20 s"* && $out != *"wartet auf dich"* ]]
echo '{"finished":true}' >"$sub/agent-a1.meta.json"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"wartet auf dich"* && $out != *"Helfer arbeiten"* ]]
echo '{}' >"$sub/agent-a1.meta.json"; touch -d 2026-11-15T13:00:00Z "$sub/agent-a1.jsonl"   # stale log: gave up
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"wartet auf dich"* ]]

# test_thinking: owner prompt, tool result, text before a tool call
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:00Z","origin":{"kind":"human"},"message":{"content":"los"}}'
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"JETZT ▶ denkt nach"* && $out == *"seit 20 s"* ]]
entry $s1 "$(assistant 14:12:05 null '[{"type":"text","text":"ich schaue nach"}]')"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"JETZT ▶ denkt nach"* && $out == *"seit 15 s"* ]]
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:10Z","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"JETZT ▶ denkt nach"* && $out == *"seit 10 s"* ]]

# test_age: seconds, minutes, hours
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:09:20 '"end_turn"' '[]')"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"seit 3 min"* ]]
entry $s1 "$(assistant 12:12:00 '"end_turn"' '[]')"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"seit 2 h"* ]]

# test_control_chars: ESC, a C1 character and a second line never reach the terminal
tool Bash '{"description":"x\u001b[2Jy\u009bz\nsecond"}'
[[ $out == *"JETZT ▶ x?[2Jy?z"* && $out != *$'\e'* && $out != *second* ]]
# every line fits the window
tool Bash '{"description":"'"$(printf 'langer Text %.0s' {1..30})"'"}'
python3 -c 'import sys; sys.exit(max(len(l) for l in sys.stdin.buffer.read().decode().split("\n")) > 46)' <<<"$out"
[[ $out == *"JETZT ▶ langer Text"*"…"* ]]

# test_ended: the only session in the folder is dead
fresh; session 999999 $s1 src-a "$HOME/w"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"JETZT ▶ Sitzung beendet"* ]]

# test_pick: the newest live session inside the folder wins; dead ones and sibling folders do not
session $$ aaaaaaaa-2 src-b "$HOME/w/a" 1794700100000
session $PPID aaaaaaaa-3 src-c "$HOME/w/b" 1794700200000
session 999998 aaaaaaaa-4 src-d "$HOME/w/c" 1794700300000
session 999997 aaaaaaaa-5 src-e "$HOME/wx" 1794700400000
out=$(lage --dir "$HOME/w" --once);  [[ $out == "LAGE  w/b"* && $out != *"Sitzung beendet"* ]]
out=$(lage --dir "$HOME/w/c" --once);  [[ $out == "LAGE  w/c"* && $out == *"Sitzung beendet"* ]]
out=$(lage --dir "$HOME/wx/" --once);  [[ $out == "LAGE  wx"* ]]

# test_none: nobody in the folder
out=$(lage --dir "$HOME/empty" --once);  [[ $out == "LAGE"*"Stand 14:12"$'\n'"kein Claude in empty" ]]

# test_no_session_files: files without sessionId or valid JSON are ignored
fresh
echo '{"peerToken":"x","pidDomain":"y","procStart":"z"}' >"$HOME/.claude/sessions/1.json"
echo '{"pid":' >"$HOME/.claude/sessions/2.json"
echo '[1]' >"$HOME/.claude/sessions/3.json"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"kein Claude in w"* ]]
session $$ $s1 src-a "$HOME/w"
out=$(lage --dir "$HOME/w" --once);  [[ $out == "LAGE  w"* ]]

# test_no_transcript
rm "$HOME/.claude/projects/p/$s1.jsonl"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"JETZT ▶ Protokoll nicht gefunden"* ]]

# test_home_cut: $HOME/src/ is cut off the header like $HOME/
fresh; session $$ $s1 src-a "$HOME/src/sec/ctf/box1"
out=$(lage --dir "$HOME/src/sec" --once);  [[ $out == "LAGE  sec/ctf/box1"* ]]

# test_board_path: one board per session; inside a lab folder one board per lab folder
fresh; session $$ $s1 src-a "$HOME/w"
[[ $(lage --dir "$HOME/w" --idea 'A' && ls "$HOME/.local/state/lage/") == $s1.md ]]
[[ $(cat "$(bfile)") == $'## Funde\n## Ungeprüft\n## Für dich\n## Deine Ideen\n- [ ] 2026-11-15 14:12 A' ]]
lage --dir "$HOME/w" --idea 'B'
[[ $(tail -n 2 "$(bfile)") == $'- [ ] 2026-11-15 14:12 A\n- [ ] 2026-11-15 14:12 B' ]]
for d in ctf/box1/sub re/a live/b/c/d; do
  fresh; session $$ bbbbbbbb-2 src-b "$HOME/src/sec/$d"
  lab=$HOME/src/sec/$(cut -d/ -f1-2 <<<"$d")
  lage --dir "$HOME/src/sec/$d" --idea 'Cookie anschauen'
  grep -qx -- '- \[ \] 2026-11-15 14:12 Cookie anschauen' "$lab/.claude/lage.md"
  [[ ! -e $HOME/.local/state && $(find "$HOME" -name lage.md) == "$lab/.claude/lage.md" ]]
done
# the lab folder itself finds the same session; its board keeps growing
lage --dir "$HOME/src/sec/live/b" --idea 'Zwei'
[[ $(grep -c . "$HOME/src/sec/live/b/.claude/lage.md") -eq 6 ]]

# test_not_a_lab (Review Focus 5): lookalike folders and the kind folders themselves keep the board in ~/.local/state
for d in ctf-old/x live-notes ctf live re-old/a; do
  fresh; session $$ cccccccc-3 src-c "$HOME/src/sec/$d"
  lage --dir "$HOME/src/sec/$d" --idea 'B'
  [[ $(find "$HOME" -name "*.md") == "$HOME/.local/state/lage/cccccccc-3.md" && ! -e $HOME/src ]]
done

# test_idea_cleaned: empty text does nothing, control characters and long text are cut, no session is an error
fresh; session $$ $s1 src-a "$HOME/w"
lage --dir "$HOME/w" --idea '   '; lage --dir "$HOME/w" --idea ''
[[ ! -e $HOME/.local/state ]]
lage --dir "$HOME/w" --idea $'x\e[2Jy\nzweite'
[[ $(tail -n 1 "$(bfile)") == '- [ ] 2026-11-15 14:12 x?[2Jy' && $(<"$(bfile)") != *$'\e'* ]]
lage --dir "$HOME/w" --idea "$(printf 'a%.0s' {1..300})"
python3 -c 'import sys; l = open(sys.argv[1], encoding="utf-8").read().splitlines()[-1]; sys.exit(len(l) != 23 + 200 or not l.endswith("…"))' "$(bfile)"
fresh; rc=0
lage --dir "$HOME/empty" --idea 'x' 2>"$t/err" || rc=$?
[[ $rc -eq 1 && $(<"$t/err") == *"kein Claude in empty"* && ! -e $HOME/.local/state ]]

# test_idea_keeps_file: add_idea changes one line and nothing else
fresh; session $$ $s1 src-a "$HOME/w"
board <<'EOF'
## Funde
- 2026-11-15 14:02 ! Admin-Login ohne Sperre
- 13:50 Port 22 offen
## Ungeprüft
- 14:05 UDP nicht gescannt
## Für dich
- 14:06 Ist 10.10.10.7 im Scope?
## Deine Ideen
- [ ] 14:10 Cookie anschauen
- [x] 13:40 robots.txt lesen → nichts drin
EOF
cp "$(bfile)" "$t/before"
lage --dir "$HOME/w" --idea 'Neu'
[[ $(diff "$t/before" "$(bfile)" | grep -c '^[<>]') -eq 1 && $(tail -n 1 "$(bfile)") == '- [ ] 2026-11-15 14:12 Neu' ]]
# the ideas section in the middle: the idea goes below its last line; blank separator and next heading stay
printf '## Deine Ideen\n- [ ] 14:10 eins\n\n## Funde\n- 14:02 x\n' | board
lage --dir "$HOME/w" --idea 'zwei'
[[ $(<"$(bfile)") == $'## Deine Ideen\n- [ ] 14:10 eins\n- [ ] 2026-11-15 14:12 zwei\n\n## Funde\n- 14:02 x' ]]
# no ideas section and no final newline: the heading is added
printf '## Funde\n- 14:02 x' | board
lage --dir "$HOME/w" --idea 'drei'
[[ $(<"$(bfile)") == $'## Funde\n- 14:02 x\n## Deine Ideen\n- [ ] 2026-11-15 14:12 drei' ]]
# an empty file; bytes that are not UTF-8 and CRLF line ends survive
: | board
lage --dir "$HOME/w" --idea 'vier'
[[ $(<"$(bfile)") == $'## Deine Ideen\n- [ ] 2026-11-15 14:12 vier' ]]
printf '## Funde\n- \xff alt\r\n## Deine Ideen\n' | board
cp "$(bfile)" "$t/before"
lage --dir "$HOME/w" --idea 'fünf'
[[ $(diff -a "$t/before" "$(bfile)" | grep -c '^[<>]') -eq 1 ]] && grep -aq alt "$(bfile)"
[[ $(ls "$HOME/.local/state/lage/") == $s1.md ]]    # no temp file left behind

# test_neu: the owner's last prompt marks newer entries; the same minute counts (Review Focus 3)
fresh; session $$ $s1 src-a "$HOME/w"
owner 14:02:40
board <<'EOF'
## Funde
- 2026-11-15 14:02 ! Admin-Login ohne Sperre
- 2026-11-15 13:50 Port 22 offen
## Für dich
- 14:09 Ist 10.10.10.7 im Scope?
EOF
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"FUNDE  2  (1 neu)"* && $out == *"NEU !  14:02 Admin-Login"* && $out == *"UNGEPRÜFT  0"* && $out == *"FÜR DICH  1  (1 neu)"* && $out == *"DEINE IDEEN  0 offen"* ]]
[[ $(grep '13:50 Port 22 offen' <<<"$out") == "    ·  13:50 Port 22 offen" ]]
[[ $out == *"NEU ·  14:09 Ist 10.10.10.7 im Scope?"* && $(grep -c NEU <<<"$out") -eq 2 ]]
# two rule lines frame the board below JETZT; every line fits
[[ $(grep -c '^──────' <<<"$out") -eq 2 && $(sed -n 4p <<<"$out") == ──────* && $(sed -n 5p <<<"$out") == "FUNDE  2  (1 neu)" && $(widest <<<"$out") -le 46 ]]
# no owner prompt in the transcript: nothing is NEU
fresh; session $$ $s1 src-a "$HOME/w"
printf '## Funde\n- 14:02 ! x\n' | board
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"FUNDE  1"$'\n'* && $out != *NEU* ]]

# test_peer_is_not_owner: helper mail and notifications do not move NEU
fresh; session $$ $s1 src-a "$HOME/w"
owner 14:02:40
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:11:00Z","origin":{"kind":"peer"},"message":{"content":"mail"}}'
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:11:30Z","origin":{"kind":"task-notification"},"message":{"content":"n"}}'
printf '## Funde\n- 14:05 spaeter\n- 14:01 frueher\n' | board
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"FUNDE  2  (1 neu)"* && $out == *"NEU ·  14:05 spaeter"* && $out != *"NEU ·  14:01"* ]]
owner 14:11:50     # a real prompt does move it
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"FUNDE  2"$'\n'* && $out != *NEU* ]]

# test_older: what does not fit collapses; each section gets max(2, (LINES - 19) // 4) lines
fresh; session $$ $s1 src-a "$HOME/w"
{ echo '## Funde'; for m in 00 01 02 03 04 05 06; do echo "- 13:$m Fund $m"; done; } | board
out=$(lage --dir "$HOME/w" --once)
funde=$(sed -n '/^FUNDE/,/^UNGEPRÜFT/p' <<<"$out")
[[ $(grep -c 'Fund 0' <<<"$funde") -eq 2 && $funde == *"13:06 Fund 06"*"13:05 Fund 05"*$'\n+5 ältere\n'* && $funde != *"Fund 04"* ]]
out=$(LINES=10 lage --dir "$HOME/w" --once);  [[ $(grep -c 'Fund 0' <<<"$out") -eq 2 && $out == *$'\n+5 ältere\n'* ]]
out=$(LINES=31 lage --dir "$HOME/w" --once);  [[ $(grep -c 'Fund 0' <<<"$out") -eq 3 && $out == *$'\n+4 ältere\n'* ]]
out=$(LINES=47 lage --dir "$HOME/w" --once);  [[ $(grep -c 'Fund 0' <<<"$out") -eq 7 && $out != *ältere* ]]

# test_old_day: an older day shows as DD.MM.
fresh; session $$ $s1 src-a "$HOME/w"
printf '## Funde\n- 2026-11-14 09:00 Gestern\n- 2026-11-15 09:00 Heute\n' | board
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"·  09:00 Heute"*"·  14.11. Gestern"* && $out != *"15.11."* ]]    # newest first

# test_wrap: long entries wrap to the text column; one longer than its section is cut
fresh; session $$ $s1 src-a "$HOME/w"
long=$(printf 'wort%02d ' {1..16})
printf '## Funde\n- 14:02 ! %s\n- 13:00 kurz\n## Deine Ideen\n- [ ] %s\n' "$long" "$long" | board
out=$(LINES=47 lage --dir "$HOME/w" --once)
[[ $(widest <<<"$out") -le 46 && $out == *"    !  14:02 wort01 "* && $(grep -c '^             wort05 ' <<<"$out") -eq 2 && $(grep -c wort16 <<<"$out") -eq 2 ]]
[[ $out == *"·        [ ] wort01 "* ]]
out=$(lage --dir "$HOME/w" --once)
[[ $(widest <<<"$out") -le 46 && $out == *"wort01 "* && $out == *"…"$'\n'* && $out == *$'\n+1 ältere\n'* && $out != *wort16* ]]
# a dated row indents one column further
fresh; session $$ $s1 src-a "$HOME/w"
printf '## Funde\n- 2026-11-14 14:02 %s\n' "$long" | board
out=$(LINES=47 lage --dir "$HOME/w" --once)
[[ $out == *"·  14.11. wort01 "* && $out == *$'\n              wort05 '* ]]

# test_ideas: open ideas first, then done ones; ideas are never NEU
fresh; session $$ $s1 src-a "$HOME/w"
owner 12:00:00
printf '## Deine Ideen\n- [x] 14:11 robots lesen → nichts drin\n- [ ] 13:00 Cookie anschauen\n- Ohne Kästchen\n' | board
out=$(LINES=47 lage --dir "$HOME/w" --once)
[[ $out == *"DEINE IDEEN  2 offen"* && $out != *NEU* ]]
[[ $out == *"·  13:00 [ ] Cookie anschauen"*"[ ] Ohne Kästchen"*"·  14:11 [x] robots lesen → nichts drin"* ]]

# test_odd_board (Review Focus 4): hand-edited boards never crash and never invent NEU
fresh; session $$ $s1 src-a "$HOME/w"
owner 14:02:40
: | board
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"FUNDE  0"* && $out == *"DEINE IDEEN  0 offen"* ]]
printf '## Notizen\n- Fund im falschen Abschnitt\n' | board
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"FUNDE  0"* && $out != *falschen* ]]
printf '## Funde\n- kein Zeitstempel\n- 13:40 nur Uhrzeit\n- 25:99 kaputt\nfreie Zeile\n- \n-\n## Funde zwei\n- anderes\n' | board
out=$(LINES=47 lage --dir "$HOME/w" --once)
[[ $out == *"FUNDE  3"$'\n'* && $out != *NEU* && $out == *"·  13:40 nur Uhrzeit"*"kein Zeitstempel"*"25:99 kaputt"* && $out != *freie* && $out != *anderes* ]]
printf '## Funde\n- 14:30 bare Uhrzeit ist heute\n' | board
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"FUNDE  1  (1 neu)"* && $out == *"NEU ·  14:30 bare"* ]]
printf '## Funde\r\n- 14:30 ! mit CRLF\r\n' | board
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"NEU !  14:30 mit CRLF"* ]]
printf '## Funde\n- 14:30 x\xff\xfe\x1b[2Jy\n' | board
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"FUNDE  1"* && $out != *$'\e'* ]]
rm "$(bfile)"; mkdir "$(bfile)"                    # a directory where the board should be
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"FUNDE  0"* ]]
rc=0; lage --dir "$HOME/w" --idea 'x' 2>"$t/err" || rc=$?;  [[ $rc -eq 1 && $(<"$t/err") == "lage: "* ]]
rmdir "$(bfile)"; printf '## Funde\n- 0001-01-01 10:00 uralt\n- 14:30 jung\n' >"$(bfile)"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"jung"*"01.01. uralt"* ]]       # a silly date neither crashes nor leads

# test_board_unit: parse_board and the highlight of ! rows, which only a terminal shows
fresh; session $$ $s1 src-a "$HOME/w"
python3 -B - "$here" <<'EOF'
import io
import sys
from datetime import date, datetime, timezone

sys.path.insert(0, sys.argv[1])
import lage

text = "## Funde\n- 2026-11-15 14:02 ! A\n- 9:05 B\n## Deine Ideen\n- [x] 13:40 C\n- [ ] D\n## Foo\n- E\n"
b = lage.parse_board(text, date(2026, 11, 15))
assert list(b) == ["Funde", "Ungeprüft", "Für dich", "Deine Ideen"], list(b)
assert b["Funde"] == [lage.Entry(datetime(2026, 11, 15, 14, 2), True, None, "A"), lage.Entry(datetime(2026, 11, 15, 9, 5), False, None, "B")], b["Funde"]
assert b["Deine Ideen"] == [lage.Entry(datetime(2026, 11, 15, 13, 40), False, True, "C"), lage.Entry(None, False, False, "D")], b["Deine Ideen"]
assert b["Ungeprüft"] == [] and b["Für dich"] == []
owner = datetime(2026, 11, 15, 14, 2, 40, tzinfo=timezone.utc)
plain = lage.board_lines(b, owner, 46, 27)
assert not any("\x1b" in x for x in plain), plain


class Tty(io.StringIO):
    def isatty(self):
        return True


sys.stdout = Tty()
lit = lage.board_lines(b, owner, 46, 27)
assert [x for x in lit if "\x1b" in x] == [x for x in lit if "A" in x and "NEU" in x], lit
assert [lage.RESET in x for x in lit if "\x1b" in x] == [True]
EOF

# test_idea_key: key i on a terminal asks for an idea (needs a pty)
fresh; session $$ $s1 src-a "$HOME/w"
python3 -B - "$here/lage.py" "$HOME/w" "$(bfile)" <<'EOF'
import os
import pty
import select
import signal
import sys
import time

prog, folder, board = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("python3", ["python3", prog, "--dir", folder])
seen = b""


def wait_for(text):
    global seen
    end = time.time() + 8
    while text not in seen and time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            seen += os.read(fd, 4096)
    assert text in seen, (text, seen[-300:])


wait_for("i = Idee eintragen".encode())
time.sleep(0.3)
os.write(fd, b"x")  # other keys do nothing
os.write(fd, b"i")
wait_for(b"Idee: ")
os.write(fd, b"Cookie anschauen\n")
wait_for(b"Cookie anschauen\r\n")  # echoed: the terminal was restored for input()
end = time.time() + 5
while not os.path.exists(board) and time.time() < end:
    time.sleep(0.1)
assert open(board, encoding="utf-8").read().splitlines()[-1] == "- [ ] 2026-11-15 14:12 Cookie anschauen"
os.kill(pid, signal.SIGINT)
assert os.waitpid(pid, 0)[1] == 0
EOF

# test_incremental: update() takes only complete new lines; the highlight appears on a terminal only
fresh; session $$ $s1 src-a "$HOME/w"
python3 -B - "$here" <<'EOF'
import io
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import lage

f = Path.home() / ".claude/projects/p/aaaaaaaa-1.jsonl"
f.write_text('{"type":"ai-title","aiTitle":"Erster"}\n')
tr = lage.Transcript("aaaaaaaa-1")
tr.update()
assert tr.title == "Erster" and tr.last is None, (tr.title, tr.last)
line = '{"type":"assistant","timestamp":"2026-11-15T14:00:00Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Soll ich?\\nzweite"}]}}'
with f.open("a") as h:
    h.write(line[:50])
pos = tr.pos
tr.update()
assert tr.last is None and tr.pos == pos, "half a line was read"
with f.open("a") as h:
    h.write(line[50:] + "\n")
tr.update()
assert tr.last["type"] == "assistant" and tr.pos == f.stat().st_size
assert tr.last_text == "Soll ich?", tr.last_text
assert tr.owner_ts is None and tr.helpers() == 0
session, ended = lage.pick_by_dir(str(Path.home() / "w"))
assert session["sessionId"] == "aaaaaaaa-1" and not ended and session["alive"]
plain = lage.frame(session, ended, "in w")
assert not any("\x1b" in x for x in plain), plain


class Tty(io.StringIO):
    def isatty(self):
        return True


sys.stdout = Tty()
assert any("\x1b" in x and "wartet auf dich" in x for x in lage.frame(session, ended, "in w"))
EOF

echo ok
