#!/usr/bin/env bash
# Test for tools/lage.py with a fake HOME, fixture sessions and transcripts, a fixed clock.
# Run: tools/lage.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); sl=(); trap 'rm -rf "$t"; ((${#sl[@]})) && kill -- "${sl[@]}" 2>/dev/null || true' EXIT
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
live() { sleep 600 & sl+=($!); pid=$!; } # live: one more running process, its pid in $pid
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
[[ $(diff -a "$t/before" "$(bfile)" | grep -c '^[<>]') -eq 1 ]]
grep -aq alt "$(bfile)"
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
# a rule below JETZT, one below the board, one above the footer (SITZUNGEN sits between the last two); every line fits
[[ $(grep -c '^──────' <<<"$out") -eq 3 && $(sed -n 4p <<<"$out") == ──────* && $(sed -n 5p <<<"$out") == "FUNDE  2  (1 neu)" && $(widest <<<"$out") -le 46 ]]
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

# test_sitzungen: waiting first, marked !; the followed session is marked ▶; only the first line of the text
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
live; session $pid bbbbbbbb-2 src-c8 "$HOME/empty"
entry bbbbbbbb-2 '{"type":"ai-title","aiTitle":"Bot-Menü","sessionId":"bbbbbbbb-2"}'
entry bbbbbbbb-2 "$(assistant 14:12:00 '"end_turn"' '[{"type":"text","text":"Soll ich es ausrollen?\nzweite Zeile"}]')"
out=$(COLUMNS=60 lage --dir "$HOME/w" --once)
blk=$(sed -n '/^SITZUNGEN/,$p' <<<"$out")
[[ $(sed -n 1p <<<"$blk") == SITZUNGEN && $(sed -n 2p <<<"$blk") == " !  src-c8  Bot-Menü  wartet: Soll ich es ausrollen?" ]]   # waiting first
[[ $(sed -n 3p <<<"$blk") == " ▶  src-a   "*"arbeitet" && $blk != *"zweite Zeile"* && $(tail -n 1 <<<"$blk") == "i = Idee eintragen" ]]
[[ $(sed -n 4p <<<"$blk") == ──────* && $(grep -c '^──────' <<<"$out") -eq 3 ]]   # a rule between the board and SITZUNGEN, one above the footer
# a line wider than the window is cut with an ellipsis, never wrapped
out=$(lage --dir "$HOME/w" --once);  line=$(grep src-c8 <<<"$out")
[[ ${#line} -eq 46 && $line == *"…" && $line == " !  src-c8  Bot-Menü  wartet: Soll ich es "* ]]
# ! wins over ▶: the followed session waits too; both wait, so by name
entry $s1 "$(assistant 14:12:10 '"end_turn"' '[{"type":"text","text":"Fertig, ok?"}]')"
out=$(COLUMNS=60 lage --dir "$HOME/w" --once);  blk=$(sed -n '/^SITZUNGEN/,$p' <<<"$out")
[[ $(sed -n 2p <<<"$blk") == " !  src-a   "*"wartet: Fertig, ok?" && $(sed -n 3p <<<"$blk") == " !  src-c8 "* && $blk != *"▶"* ]]
# helpers running: Helfer arbeiten, not waiting, no !
sub=$HOME/.claude/projects/p/bbbbbbbb-2/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-a1.meta.json"; echo '{}' >"$sub/agent-a1.jsonl"; touch -d 2026-11-15T14:10:00Z "$sub/agent-a1.jsonl"
out=$(COLUMNS=60 lage --dir "$HOME/w" --once)
[[ $(grep src-c8 <<<"$out") == "    src-c8  Bot-Menü  Helfer arbeiten" ]]

# test_sitzungen_names: no name or an empty one → first 6 characters of the session id; topic and name are cut; control characters never reach the terminal
fresh; session $$ $s1 src-a "$HOME/w"
live; echo '{"pid":'"$pid"',"sessionId":"deadbe12-3456","cwd":"/x","startedAt":1794700000000}' >"$HOME/.claude/sessions/$pid.json"
live; session $pid cafe0000-1 "" "$HOME/empty"
entry cafe0000-1 '{"type":"ai-title","aiTitle":"Dies ist ein sehr langer Titel","sessionId":"cafe0000-1"}'
live; session $pid evil0000-1 '\u001b[31mevil name that is long' "$HOME/empty"
entry evil0000-1 '{"type":"ai-title","aiTitle":"a\u001b[0mb\u009bc","sessionId":"evil0000-1"}'
out=$(COLUMNS=80 lage --dir "$HOME/w" --once)
[[ $out == *" !  deadbe "*"wartet"* && $out == *" !  cafe00 "*"Dies ist ei…  wartet"* ]]
[[ $out == *"?[31mevil n…  a?[0mb?c "*"wartet"* && $out != *$'\x1b'* && $out != *$'\xc2\x9b'* ]]
[[ $(widest <<<"$out") -le 80 ]]

# test_dead_hidden: a session whose pid is gone has no line; without any line the block and its rule are gone
fresh; session $$ $s1 src-a "$HOME/w"
session 999999 dddddddd-4 src-dead "$HOME/empty"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *src-a* && $out != *src-dead* ]]
fresh; session 999999 dddddddd-4 src-dead "$HOME/w"
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"Sitzung beendet"* && $out != *SITZUNGEN* && $out != *src-dead* && $(grep -c '^──────' <<<"$out") -eq 2 ]]

# test_cap: 8 alive sessions → 6 lines and "+2 weitere"; the working one sorts last and is cut; no line wider than the window
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
for i in 1 2 3 4 5 6 7; do live; session $pid "cap0000$i-1" "src-$i" "$HOME/empty"; done
out=$(lage --dir "$HOME/w" --once)
blk=$(sed -n '/^SITZUNGEN/,/^──/p' <<<"$out" | sed '1d;$d')
[[ $(wc -l <<<"$blk") -eq 7 && $(tail -n 1 <<<"$blk") == "+2 weitere" && $(grep -c 'wartet' <<<"$blk") -eq 6 && $blk == *src-6* && $blk != *src-7* && $blk != *src-a* ]]
[[ $(sed -n 1p <<<"$blk") == " !  src-1 "*"wartet" && $(widest <<<"$out") -le 46 ]]
# exactly 6 sessions: no "+N weitere"
fresh; session $$ $s1 src-a "$HOME/w"
for i in 1 2 3 4 5; do live; session $pid "cap0000$i-1" "src-$i" "$HOME/empty"; done
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"src-5"* && $out != *weitere* ]]

# test_sitzungen_cache: a transcript is kept across refreshes and only its new bytes are read
fresh; session $$ $s1 src-a "$HOME/w"; live
python3 -B - "$here" $pid <<'EOF'
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import lage

home = Path.home()
pid = int(sys.argv[2])
(home / ".claude/sessions" / f"{pid}.json").write_text(json.dumps({"pid": pid, "sessionId": "bbbbbbbb-2", "name": "src-b", "cwd": "/x"}))
f = home / ".claude/projects/p/bbbbbbbb-2.jsonl"
entry = '{"type":"assistant","timestamp":"2026-11-15T14:12:00Z","message":{"stop_reason":"%s","content":[%s]}}\n'
tool = entry % ("tool_use", '{"type":"tool_use","name":"Read","input":{}}')
f.write_text('{"type":"ai-title","aiTitle":"Alt","sessionId":"bbbbbbbb-2"}\n' + tool)
os.environ["LAGE_NOW"] = "2026-11-15T14:12:20Z"
first = lage.sitzungen_lines("aaaaaaaa-1", 60)
assert first[0] == "SITZUNGEN" and any("src-b" in x and "Alt" in x and x.endswith("arbeitet") for x in first), first
tr = lage.transcripts["bbbbbbbb-2"]
assert tr.pos == f.stat().st_size
with f.open("a") as h:
    h.write('{"type":"ai-title","aiTitle":"Neu","sessionId":"bbbbbbbb-2"}\n')
    h.write(entry % ("end_turn", '{"type":"text","text":"Fertig?"}'))
second = lage.sitzungen_lines("aaaaaaaa-1", 60)
assert lage.transcripts["bbbbbbbb-2"] is tr and tr.pos == f.stat().st_size
assert any("src-b" in x and "Neu" in x and x.endswith("wartet: Fertig?") for x in second), second
before = tr.pos
lage.sitzungen_lines("aaaaaaaa-1", 60)
assert tr.pos == before
EOF

hook() { # hook <event> <session id> [agent id]: the hook JSON on stdin (cwd $HOME/w), the hook's output on stdout
  jq -nc --arg e "$1" --arg s "$2" --arg c "$HOME/w" --arg a "${3:-}" \
    '{hook_event_name: $e, session_id: $s, cwd: $c} + (if $a == "" then {} else {agent_id: $a} end)' | lage hook; }
context() { jq -r .hookSpecificOutput.additionalContext; } # the text Claude gets, from the hook output on stdin

# test_hook_start_tells_path: no board yet; the hook never creates one
fresh
out=$(hook SessionStart $s1)
[[ $(context <<<"$out") == "Lage-Board: $HOME/.local/state/lage/$s1.md" && $(jq -r .hookSpecificOutput.hookEventName <<<"$out") == SessionStart ]]
[[ -z $(hook UserPromptSubmit $s1) && ! -e $HOME/.local/state ]]

# test_hook_idea_once: a new open idea is shown once, escaped as JSON; the state file holds hashes only
fresh; session $$ $s1 src-a "$HOME/w"
lage --dir "$HOME/w" --idea 'Cookie "anschauen" \ ü'
out=$(hook PostToolUse $s1)
[[ $(jq -r .hookSpecificOutput.hookEventName <<<"$out") == PostToolUse ]]
[[ $(context <<<"$out") == 'Neue Idee von vino: Cookie "anschauen" \ ü' ]]
[[ -z $(hook PostToolUse $s1) && -z $(hook UserPromptSubmit $s1) ]]
shown=$HOME/.local/state/lage/$s1.shown
[[ -s $shown && $(grep -c Cookie "$shown" || true) == 0 && $(grep -vc '^[0-9a-f]\{64\}$' "$shown" || true) == 0 ]]
lage --dir "$HOME/w" --idea 'zweite'
[[ $(hook PostToolUse $s1 | context) == 'Neue Idee von vino: zweite' ]]

# test_hook_start_with_ideas: SessionStart gives the path, then the ideas not shown yet, one per line
fresh; session $$ $s1 src-a "$HOME/w"
lage --dir "$HOME/w" --idea 'eins'; lage --dir "$HOME/w" --idea 'zwei'
[[ $(hook SessionStart $s1 | context) == "Lage-Board: $HOME/.local/state/lage/$s1.md"$'\nNeue Idee von vino: eins\nNeue Idee von vino: zwei' ]]
[[ $(hook SessionStart $s1 | context) == "Lage-Board: $HOME/.local/state/lage/$s1.md" ]]

# test_hook_done_idea_not_shown: only open ideas under Deine Ideen
fresh
board <<'EOF'
## Funde
- 14:00 ! ein Fund
## Für dich
- 14:00 wichtig
## Deine Ideen
- [x] 2026-11-15 14:00 erledigt
- [ ] 2026-11-15 14:01 offen
EOF
[[ $(hook PostToolUse $s1 | context) == 'Neue Idee von vino: offen' ]]
[[ -z $(hook PostToolUse $s1) ]]

# test_hook_helper_skipped: a helper's call says nothing; the next main call still shows the idea
fresh; session $$ $s1 src-a "$HOME/w"
lage --dir "$HOME/w" --idea 'für den Hauptlauf'
[[ -z $(hook PostToolUse $s1 a1) && -z $(hook SessionStart $s1 a1) && ! -e $HOME/.local/state/lage/$s1.shown ]]
[[ $(hook PostToolUse $s1 | context) == 'Neue Idee von vino: für den Hauptlauf' ]]

# test_hook_no_board: a session without a board gets no output and no file
fresh
out=$(hook PostToolUse cccccccc-3); [[ -z $out && ! -e $HOME/.local/state ]]

# test_hook_bad_id: anything but lowercase hex and dashes (8+) is ignored; nothing outside the state folder is read
fresh; mkdir -p "$HOME/.local/state/lage"
for f in ../x.md abcdef.md AAAAAAAA-1.md; do printf '## Deine Ideen\n- [ ] 2026-11-15 14:00 Falle\n' >"$HOME/.local/state/lage/$f"; done
for bad in ../x abcdef AAAAAAAA-1 $'aaaaaaaa-1\n' ''; do
  rc=0; out=$(hook PostToolUse "$bad" 2>&1) || rc=$?; [[ $rc -eq 0 && -z $out ]]
done
[[ -z $(ls "$HOME/.local/state/lage" | grep shown || true) && ! -e $HOME/.local/state/x.shown ]]

# test_hook_never_fails: empty or odd stdin gives exit 0 and no output
for bad in '' '{bad' '[]' null '{"session_id":5,"hook_event_name":"PostToolUse"}' '{"session_id":"aaaaaaaa-1"}'; do
  rc=0; out=$(printf '%s' "$bad" | lage hook 2>&1) || rc=$?; [[ $rc -eq 0 && -z $out ]]
done

# test_hook_start_cwd: the board follows the session file's start folder, not the hook's cwd; lab text never leaves the lab folder
fresh; mkdir -p "$HOME/src/sec/live/b/sub"; session $$ $s1 src-a "$HOME/src/sec/live/b/sub"
lage --dir "$HOME/src/sec/live/b" --idea 'Cookie im Labor'
[[ $(hook SessionStart $s1 | context) == "Lage-Board: $HOME/src/sec/live/b/.claude/lage.md"$'\nNeue Idee von vino: Cookie im Labor' ]]
[[ $(ls "$HOME/.local/state/lage") == $s1.shown && -z $(grep -rl Cookie "$HOME/.local/state" || true) ]]

# The Cockpit master window: fake hyprctl and tmux on PATH, a fake claude per window, no real Hyprland.
mkdir -p "$t/bin" "$t/exe"
printf '#!/bin/sh\nsleep 60\n' >"$t/bin/claude"                      # its /proc comm is "claude"
printf '#!/bin/sh\nprintf "%%s\\n" "$CLIENTS"\n' >"$t/bin/hyprctl"     # hyprctl clients -j: $CLIENTS
cat >"$t/bin/tmux" <<'FAKE'
#!/bin/sh
[ "$1" = list-clients ] && { printf '%s\n' "$TMUX_CLIENTS"; exit 0; }
sleep 60
FAKE
chmod +x "$t"/bin/*
export PATH=$t/bin:$PATH
py=$(command -v python3)
die() { echo "FAIL: $*" >&2; exit 1; } # the ERR trap does not reach into functions
waitcomm() { local i; for i in {1..100}; do [[ $(cat /proc/$1/comm 2>/dev/null) == "$2" ]] && return 0; sleep 0.05; done; die "process $1 never became $2"; } # waitcomm <pid> <comm>
window() { # window <program> [args]: a shell standing in for kitty, the program its child. Sets $wrapper and $child.
  local i; rm -f "$t/child"
  setsid sh -c '"$@" & echo $! >"$0"; wait; sleep 60' "$t/child" "$@" &
  wrapper=$!; sl+=("-$wrapper")                                         # the whole process group dies in the trap
  for i in {1..100}; do [[ -s $t/child ]] && break; sleep 0.05; done
  child=$(<"$t/child"); waitcomm "$child" "${1##*/}"
}
cl() { # cl <pid> <class> <workspace> <x> <y> [hidden] [floating] [focusHistoryID]: one client as hyprctl prints it
  jq -nc --argjson p "$1" --arg c "$2" --argjson w "$3" --argjson x "$4" --argjson y "$5" --argjson h "${6:-false}" --argjson f "${7:-false}" --argjson i "${8:-0}" \
    '{pid: $p, class: $c, workspace: {id: $w}, at: [$x, $y], hidden: $h, floating: $f, focusHistoryID: $i}'; }
clients() { CLIENTS=$(printf '%s\n' "$@" | jq -sc .); export CLIENTS; } # clients <cl output>...
probe() { rc=0; out=$(lage --probe "$1" 2>&1) || rc=$?; [[ -z $out ]] || die "--probe $1 printed: $out"; } # probe <pid>: exit code in $rc, never any output

# test_probe: exit 0 when a claude with a sessions file runs below the window, else 1, always silent
fresh; window "$t/bin/claude"; session $child $s1 src-a "$HOME/w"
probe $wrapper; [[ $rc -eq 0 ]]
live; probe $pid; [[ $rc -eq 1 ]]                                       # a plain sleep
probe 999999; [[ $rc -eq 1 ]]                                           # no such process
rm "$HOME/.claude/sessions/$child.json"; probe $wrapper; [[ $rc -eq 1 ]] # claude without a sessions file
# deeper down, the first claude WITH a sessions file wins
fresh; window sh -c '"$0" & "$0" & wait' "$t/bin/claude"
kids=($(pgrep -P $child)); [[ ${#kids[@]} -eq 2 ]]
waitcomm ${kids[0]} claude; waitcomm ${kids[1]} claude
probe $wrapper; [[ $rc -eq 1 ]]
session ${kids[1]} $s1 src-a "$HOME/w"; probe $wrapper; [[ $rc -eq 0 ]]

# test_master: the session in the master window of the workspace of lage's own window
fresh; window "$t/bin/claude"; w1=$wrapper; session $child $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"prüft die Webseite"}}]')"
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $w1 kitty 3 0 0)" "$(cl 1 kitty 3 0 0 true)" "$(cl 1 kitty 4 0 0)"
out=$(lage --once)
[[ $out == "LAGE  w"*"Stand 14:12"* && $out == *"JETZT ▶ prüft die Webseite"* && $out != *"kein Claude"* ]]
lage --idea 'fürs Hauptfenster'; grep -q 'fürs Hauptfenster' "$(bfile)"   # --idea without --dir: the master window's session
# smallest at[0] then at[1]; floating windows, other workspaces and lage's own class never count; a hidden tab drops out
s2=bbbbbbbb-2; window "$t/bin/claude"; w2=$wrapper; session $child $s2 src-b "$HOME/empty"
clients "$(cl $$ cockpit-log 3 0 0)" "$(cl $w1 kitty 3 0 10)" "$(cl $w2 kitty 3 0 5)" "$(cl $w1 kitty 3 0 0 false true)" "$(cl $w1 kitty 4 -1 0)"
[[ $(lage --once) == "LAGE  empty"* ]]                                # y breaks the tie at x 0
clients "$(cl $$ cockpit-log 3 0 0)" "$(cl $w1 kitty 3 100 0)" "$(cl $w2 kitty 3 0 900)"
[[ $(lage --once) == "LAGE  empty"* ]]                                # x counts first
clients "$(cl $$ cockpit-log 3 0 0)" "$(cl $w1 kitty 3 0 0 true)" "$(cl $w2 kitty 3 0 0)"
[[ $(lage --once) == "LAGE  empty"* ]]                                # tab group: the visible tab
clients "$(cl $$ cockpit-log 3 0 0)" "$(cl $w1 kitty 3 0 0)" "$(cl $w2 kitty 3 0 0 true)"
[[ $(lage --once) == "LAGE  w"* ]]                                    # after a tab switch: the other one
# real groups: all tabs share `at` and none is hidden; the one focused most recently (lowest focusHistoryID) is on top
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $w1 kitty 3 0 0 false false 1)" "$(cl $w2 kitty 3 0 0 false false 0)"
[[ $(lage --once) == "LAGE  empty"* ]]
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $w1 kitty 3 0 0 false false 0)" "$(cl $w2 kitty 3 0 0 false false 1)"
[[ $(lage --once) == "LAGE  w"* ]]

# test_master_none: no claude under the master window, no hyprctl, no own window, no candidate
fresh; live; clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $pid kitty 3 0 0)"
rc=0; out=$(lage --once) || rc=$?; [[ $rc -eq 0 && $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" && $(sed -n 1p <<<"$out") == "LAGE"*"Stand 14:12" ]]
rc=0; out=$(lage --idea x 2>&1) || rc=$?; [[ $rc -eq 1 && $out == "lage: kein Claude im Hauptfenster" ]]
rc=0; out=$(PATH=$t/none "$py" "$here/lage.py" --once) || rc=$?  # test_no_hyprctl
[[ $rc -eq 0 && $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" ]]
CLIENTS='Hyprland is not running' out=$(lage --once); [[ $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" ]]
clients "$(cl 999999 kitty 3 0 0)"; out=$(lage --once); [[ $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" ]]  # no own window
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $pid kitty 3 0 0 false true)" "$(cl $pid kitty 4 0 0)"
out=$(lage --once); [[ $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" ]]                                # no candidate

# test_tmux: the kitty runs a tmux client; its pane holds the claude
fresh; window "$t/bin/tmux" client; w1=$wrapper; tm=$child
window "$t/bin/claude"; session $child $s1 src-a "$HOME/w"; cc=$child   # outside the first window
probe $w1; [[ $rc -eq 1 ]]                                              # list-clients names no pane
TMUX_CLIENTS="$tm $cc" probe $w1; [[ $rc -eq 0 ]]
TMUX_CLIENTS="$tm $pid" probe $w1; [[ $rc -eq 1 ]]                       # a pane without claude
TMUX_CLIENTS="$((tm + 1)) $cc" probe $w1; [[ $rc -eq 1 ]]                # only the client below this window counts
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $w1 kitty 3 0 0)"
[[ $(TMUX_CLIENTS="$tm $cc" lage --once) == "LAGE  w"* ]]
# no tmux on PATH: the client's own binary answers (here a copy of bash named tmux that runs ./list-clients)
cp "$(readlink -f /bin/sh)" "$t/exe/tmux"; printf 'printf "%%s\\n" "$TMUX_CLIENTS"\n' >"$t/exe/list-clients"
window "$t/exe/tmux" -c 'sleep 60; :'; tm=$child
rc=0; out=$(cd "$t/exe" && TMUX_CLIENTS="$tm $cc" PATH=$t/none "$py" "$here/lage.py" --probe $wrapper 2>&1) || rc=$?
[[ $rc -eq 0 && -z $out ]]
rc=0; out=$(cd "$t/exe" && TMUX_CLIENTS="$tm $pid" PATH=$t/none "$py" "$here/lage.py" --probe $wrapper 2>&1) || rc=$?
[[ $rc -eq 1 && -z $out ]]

# test_master_ended: the session goes away; the board stays with "Sitzung beendet" until another session turns up
fresh; window "$t/bin/claude"; session $child $s1 src-a "$HOME/w"
board <<'EOF2'
## Funde
- 14:00 ! ein Fund
EOF2
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $wrapper kitty 3 0 0)"
poll() { local i; for i in {1..150}; do grep -q "$1" "$t/out" && return 0; sleep 0.1; done; die "never printed: $1"; } # poll <text>: wait for the loop to print it
"$py" "$here/lage.py" </dev/null >"$t/out" 2>&1 & sl+=($!)
poll 'JETZT ▶ wartet auf dich'
rm "$HOME/.claude/sessions/$child.json"
poll 'JETZT ▶ Sitzung beendet'
[[ $(grep -c 'ein Fund' "$t/out") -ge 2 && -z $(grep 'kein Claude' "$t/out" || true) ]]     # the board is kept, no "kein Claude"
session $child $s1 src-a "$HOME/w"
before=$(grep -c 'JETZT ▶ wartet auf dich' "$t/out"); for i in {1..150}; do [[ $(grep -c 'JETZT ▶ wartet auf dich' "$t/out") -gt $before ]] && break; sleep 0.1; done
[[ $(grep -c 'JETZT ▶ wartet auf dich' "$t/out") -gt $before ]]                              # found again

echo ok
