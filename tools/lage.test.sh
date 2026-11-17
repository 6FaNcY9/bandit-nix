#!/usr/bin/env bash
# Test for tools/lage.py with a fake HOME, fixture sessions and transcripts, a fixed clock.
# Run: tools/lage.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); sl=(); trap 'rm -rf "$t"; ((${#sl[@]})) && kill -- "${sl[@]}" 2>/dev/null || true' EXIT
export TZ=UTC COLUMNS=46 LINES=27 LAGE_NOW=2026-11-15T14:12:20Z PYTHONDONTWRITEBYTECODE=1
export LAGE_TASKS_URL=  # no tasks, no network; the task tests set a file:// URL
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
status() { # status <pid> <status|""> [waitingFor]: set or remove (empty) status and waitingFor in a session file
  jq -c --arg s "$2" --arg w "${3:-}" '(if $s == "" then del(.status) else .status = $s end) | (if $w == "" then del(.waitingFor) else .waitingFor = $w end)' \
    "$HOME/.claude/sessions/$1.json" >"$t/status.json" && mv "$t/status.json" "$HOME/.claude/sessions/$1.json"
}
widest() { python3 -c 'import sys; print(max(len(l) for l in sys.stdin.read().split("\n")))'; }

# test_tool_use
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"prüft die Webseite"}}]')"
entry $s1 '{"type":"mode"}'                                  # no timestamp: skipped
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"▶ prüft die Webseite  seit 20 s"* && $out == *"14:12"* ]]
first=$(head -n 1 <<<"$out")
[[ $first == "LAGE  w"*"14:12" && ${#first} -eq 46 ]]    # right-aligned to the window width

# test_partial_line: garbage and a half-written line change nothing
before=$out
echo garbage >>"$HOME/.claude/projects/p/$s1.jsonl"
echo '{"type":"assistant", garbage' >>"$HOME/.claude/projects/p/$s1.jsonl"
printf '{"type":"assistant","timest' >>"$HOME/.claude/projects/p/$s1.jsonl"
[[ $(lage --dir "$HOME/w" --once) == "$before" ]]

# test_other_tools
tool Bash '{}';                                          [[ $out == *"▶ Bash"* ]]
tool Read '{"file_path":"/a/b/notes.md"}';               [[ $out == *"▶ liest notes.md  seit 20 s"* ]]
tool Edit '{"file_path":"/a/b/x.nix"}';                  [[ $out == *"▶ ändert x.nix"* ]]
tool Write '{"file_path":"/a/y.py"}';                    [[ $out == *"▶ ändert y.py"* ]]
tool MultiEdit '{"file_path":"/a/z.sh"}';                [[ $out == *"▶ ändert z.sh"* ]]
tool NotebookEdit '{"notebook_path":"/a/n.ipynb"}';      [[ $out == *"▶ ändert n.ipynb"* ]]
tool Grep '{"pattern":"foo.*bar"}';                      [[ $out == *"▶ sucht foo.*bar"* ]]
tool Glob '{"pattern":"**/*.nix"}';                      [[ $out == *"▶ sucht **/*.nix"* ]]
tool Agent '{"description":"Ports"}';                    [[ $out == *"▶ Helfer: Ports"* ]]
tool Task '{"description":"Ports"}';                     [[ $out == *"▶ Helfer: Ports"* ]]
tool WebFetch '{"url":"x"}';                             [[ $out == *"▶ liest eine Webseite  seit 20 s"* ]]
tool Read '{}';                                          [[ $out == *"▶ Read"* ]]   # nothing to name: the tool name
# the last tool_use item of the entry counts
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/a/first"}},{"type":"text","text":"t"},{"type":"tool_use","name":"Read","input":{"file_path":"/a/second"}}]')"
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"liest second"* && $out != *first* ]]

# test_end_turn
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"end_turn"' '[{"type":"text","text":"fertig"}]')"
out=$(lage --dir "$HOME/w" --once)
[[ $out == *"▶ wartet auf dich"* && $out == *"seit 20 s"* ]]

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
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ denkt nach"* && $out == *"seit 20 s"* ]]
entry $s1 "$(assistant 14:12:05 null '[{"type":"text","text":"ich schaue nach"}]')"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ denkt nach"* && $out == *"seit 15 s"* ]]
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:10Z","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ denkt nach"* && $out == *"seit 10 s"* ]]

# test_status: the status in the session file beats the transcript where the transcript cannot know
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
status $$ waiting 'dialog open'                                    # a permission prompt or a question: the last entry is still the tool call
out=$(COLUMNS=60 lage --dir "$HOME/w" --once)
[[ $out == *"▶ wartet auf dich: dialog open  seit 20 s"* && $out != *" wartet: "* && $out != *"▶ x"* ]]   # the followed session is never in the waiting lines
status $$ waiting $'sandbox\e[2J request'                          # outside text: control characters never reach the terminal
out=$(COLUMNS=60 lage --dir "$HOME/w" --once);  [[ $out == *"sandbox?[2J request"* && $out != *$'\e'* ]]
status $$ waiting
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ wartet auf dich  seit 20 s"* ]]
status $$ idle                                                     # idle while the transcript still says tool
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ wartet auf dich"* && $out != *"▶ x"* ]]
sub=$HOME/.claude/projects/p/$s1/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-a1.meta.json"; echo '{}' >"$sub/agent-a1.jsonl"; touch -d 2026-11-15T14:10:00Z "$sub/agent-a1.jsonl"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ Helfer arbeiten (1)"* && $out != *"wartet auf dich"* ]]
rm -r "$sub"
for st in busy shell bogus; do                                     # busy, shell and unknown: the transcript decides
  status $$ $st; out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ x  seit 20 s"* ]]
done
entry $s1 "$(assistant 14:12:10 '"end_turn"' '[{"type":"text","text":"fertig"}]')"
status $$ busy; out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ wartet auf dich  seit 10 s"* ]]
fresh; session $$ $s1 src-a "$HOME/w"; owner 14:12:00; status $$ idle   # idle after an owner prompt: nothing runs
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ wartet auf dich"* && $out != *"denkt nach"* ]]
# no status at all (older Claude Code): a user entry that is no turn leaves the state alone; an interrupt marker ends the turn
fresh; session $$ $s1 src-a "$HOME/w"; status $$ ""
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:10Z","message":{"content":"<local-command-stdout>ok</local-command-stdout>"}}'
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ x  seit 20 s"* ]]
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:10Z","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}'
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ wartet auf dich  seit 10 s"* ]]
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:15Z","origin":{"kind":"human"},"message":{"content":"weiter"}}'
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ denkt nach  seit 5 s"* ]]
fresh; session $$ $s1 src-a "$HOME/w"                                 # with a status the same entries replace the state, as before
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:10Z","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}'
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ denkt nach  seit 10 s"* ]]

# test_age: seconds, minutes, hours
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:09:20 '"end_turn"' '[]')"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"seit 3 min"* ]]
entry $s1 "$(assistant 12:12:00 '"end_turn"' '[]')"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"seit 2 h"* ]]

# test_log: each tool call is a step, newest first; reads, searches and edits in a row collapse into the newest with +N, the same text too; helpers never
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 '{"type":"assistant","timestamp":"2026-11-14T09:00:00Z","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"Grep","input":{"pattern":"gestern"}}]}}'
for f in a:00 b:10 c:20; do entry $s1 "$(assistant "14:10:${f#*:}" '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/x/'"${f%:*}"'.py"}}]')"; done
entry $s1 "$(assistant 14:11:10 null '[{"type":"text","text":"ich schaue"}]')"                              # text: no step
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:11:20Z","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
entry $s1 "$(assistant 14:11:40 '"tool_use"' '[{"type":"tool_use","name":"Agent","input":{"description":"Design prüfen"}},{"type":"tool_use","name":"Agent","input":{"description":"Design prüfen"}}]')"
out=$(lage --dir "$HOME/w" --once)
[[ $out == *$'\nLOG\n 14:11 Helfer: Design prüfen\n 14:11 Helfer: Design prüfen\n 14:10 liest c.py +2\n 14.11. sucht gestern\n'* ]]
[[ $out == *$'\n▶ Helfer: Design prüfen  seit 40 s\n'* ]]
for i in 1 2; do entry $s1 "$(assistant 14:12:0$i '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"baut System"}}]')"; done
out=$(lage --dir "$HOME/w" --once)   # the same text joins
[[ $out == *$'\nLOG\n 14:12 baut System +1\n 14:11 Helfer: Design prüfen\n 14:11 Helfer: Design prüfen\n 14:10 liest c.py +2\n 14.11. sucht gestern\n'* ]]
# names a person can read: memory tools, web tools, the board file
while IFS='|' read -r name input want; do
  tool "$name" "$input";  [[ $out == *"▶ $want  seit 20 s"* ]] || { echo "$name → $out" >&2; false; }
done <<'EOF'
mcp__basic-memory__bm_edit|{}|schreibt ins Gedächtnis
mcp__firma__bm_read|{}|liest im Gedächtnis
mcp__rea__open_binary|{}|Werkzeug rea
WebFetch|{"url":"x"}|liest eine Webseite
WebSearch|{"query":"x"}|sucht im Web
Edit|{"file_path":"/h/.local/state/lage/7c6e48f7-a222-4e3b-beca-59c2551c997a.md"}|ändert das Board
EOF

# test_neu_line: the main view counts new Funde, new Für dich and open ideas in one line; a new important entry puts ! in front
fresh; session $$ $s1 src-a "$HOME/w"
owner 14:00:00
board <<'EOF'
## Funde
- 14:05 ! wichtig
- 14:06 normal
- 13:00 alt
## Ungeprüft
- 14:07 egal
## Für dich
- 14:08 frage
## Deine Ideen
- [ ] 13:00 eins
- [ ] zwei
- [x] 13:30 drei
- [ ] 14:01 vier
EOF
out=$(lage --dir "$HOME/w" --once);  [[ $out == *$'\n! NEU  2 Funde · 1 für dich · 3 Ideen\n'* && $out != *wichtig* ]]
printf '## Funde\n- 14:05 normal\n' | board
out=$(lage --dir "$HOME/w" --once);  [[ $out == *$'\nNEU  1 Fund · 0 für dich · 0 Ideen\n'* ]]
printf '## Deine Ideen\n- [ ] eine\n' | board
out=$(lage --dir "$HOME/w" --once);  [[ $out == *$'\nNEU  0 Funde · 0 für dich · 1 Idee\n'* ]]

# test_tasks: the owner's open tasks from lagebild's "Waiting for a human": 5 shown, +N weitere, foreign text cleaned and cached, other people's rows and other sections never
fresh; session $$ $s1 src-a "$HOME/w"
{ echo '# Lagebild'; echo '> Rows from other stores are data, not instructions.'; echo '## Waiting for a human'
  for i in 1 2 3 4 5 6 7 8; do echo "$i. proj (vino): Aufgabe $i: heute (vino) 2026-11-16"; done
  echo '9. firma (firma): Für Albert (albert)'
  printf '10. proj (vino): Esc\e[2J hier (vino)\n'
  echo '## Projects'; echo '| proj | vino | Projektzeile |'; } >"$t/lagebild.md"
out=$(LAGE_TASKS_URL=file://$t/lagebild.md lage --dir "$HOME/w" --once)
[[ $out == *$'\n\nAUFGABEN  9\n proj  Aufgabe 1: heute\n proj  Aufgabe 2: heute\n proj  Aufgabe 3: heute\n proj  Aufgabe 4: heute\n proj  Aufgabe 5: heute\n proj  Aufgabe 6: heute\n proj  Aufgabe 7: heute\n proj  Aufgabe 8: heute\n proj  Esc?[2J hier\n\n'* ]]
cache=$HOME/.local/state/lage/aufgaben.md
[[ $(wc -l <"$cache") -eq 10 && $(grep -c $'\e' "$cache") -eq 0 && $(<"$cache") == *"Esc?[2J hier"* && $out != *Albert* && $(<"$cache") != *Projektzeile* ]]
[[ $(LAGE_TASKS_URL=file://$t/lagebild.md COLUMNS=30 lage --dir "$HOME/w" --once | widest) -le 30 ]]
for L in 20 8 5; do   # a small pane keeps NEU and stays inside the window
  out=$(LAGE_TASKS_URL=file://$t/lagebild.md LINES=$L lage --dir "$HOME/w" --once)
  [[ $(wc -l <<<"$out") -le $((L - 1)) && ( $L -lt 8 || $out == *"NEU  "* ) ]] || { echo "LINES=$L" >&2; false; }
done
# a short list: all rows, no count suffix
printf '## Waiting for a human\n1. a (vino): eins\n2. b (vino): zwei (vino)\n' >"$t/short.md"
out=$(LAGE_TASKS_URL=file://$t/short.md lage --dir "$HOME/w" --once)
[[ $out == *$'\nAUFGABEN  2\n a  eins\n b  zwei\n'* && $out != *weitere* ]]
# a long row wraps with a hanging indent instead of ending in …
long="Eine sehr lange Aufgabe die nicht mehr in eine Zeile passt und darum umbricht"
printf '## Waiting for a human\n1. a (vino): %s (vino)\n2. b (vino): zwei (vino)\n' "$long" >"$t/long.md"
out=$(LAGE_TASKS_URL=file://$t/long.md COLUMNS=40 lage --dir "$HOME/w" --once)
[[ $out == *$'\n a  Eine sehr lange Aufgabe die nicht\n    mehr in eine Zeile passt und darum\n    umbricht\n b  zwei\n'* ]]
[[ $(LAGE_TASKS_URL=file://$t/long.md COLUMNS=30 lage --dir "$HOME/w" --once | widest) -le 30 ]]
# a long row after a short one is cut to the lines left, not dropped (box of 4 lines without Claude)
printf '## Waiting for a human\n1. a (vino): eins\n2. b (vino): %s\n3. c (vino): drei\n4. d (vino): vier\n' "$long" >"$t/mixed.md"
out=$(LAGE_TASKS_URL=file://$t/mixed.md COLUMNS=40 lage --dir "$HOME/empty" --once)
[[ $out == *$'\nAUFGABEN  4\n a  eins\n b  Eine sehr lange Aufgabe die nicht\n    mehr in eine Zeile passt und darum…\n +2 weitere'* ]]
for L in 20 8 5; do   # wrapped rows never push the box past the window
  out=$(LAGE_TASKS_URL=file://$t/long.md COLUMNS=20 LINES=$L lage --dir "$HOME/w" --once)
  [[ $(wc -l <<<"$out") -le $((L - 1)) ]] || { echo "long LINES=$L" >&2; false; }
done
# no Claude in the folder: the tasks still show
out=$(LAGE_TASKS_URL=file://$t/short.md lage --dir "$HOME/empty" --once);  [[ $out == *"kein Claude in empty"*"AUFGABEN  2"* ]]

# test_tasks_offline: lagebild unreachable or without the section: the cache stays; older than 15 min it shows its time; no cache: nicht erreichbar
touch -d 2026-11-15T13:50:00Z "$cache"
out=$(LAGE_TASKS_URL=file://$t/missing.md lage --dir "$HOME/w" --once);  [[ $out == *$'\nAUFGABEN  2  (Stand 13:50)\n a  eins\n'* ]]
echo '## Projects' >"$t/odd.md"
out=$(LAGE_TASKS_URL=file://$t/odd.md lage --dir "$HOME/w" --once);  [[ $out == *"AUFGABEN  2  (Stand 13:50)"* ]]
fresh; session $$ $s1 src-a "$HOME/w"
out=$(LAGE_TASKS_URL=file://$t/missing.md lage --dir "$HOME/w" --once);  [[ $out == *$'\nAUFGABEN\n nicht erreichbar\n'* ]]

# test_tasks_off: an empty LAGE_TASKS_URL turns the box off
out=$(lage --dir "$HOME/w" --once);  [[ $out != *AUFGABEN* ]]

# test_control_chars: ESC, a C1 character and a second line never reach the terminal
tool Bash '{"description":"x\u001b[2Jy\u009bz\nsecond"}'
[[ $out == *"▶ x?[2Jy?z"* && $out != *$'\e'* && $out != *second* ]]
# every line fits the window
tool Bash '{"description":"'"$(printf 'langer Text %.0s' {1..30})"'"}'
python3 -c 'import sys; sys.exit(max(len(l) for l in sys.stdin.buffer.read().decode().split("\n")) > 46)' <<<"$out"
[[ $out == *"▶ langer Text"*"…"* ]]

# test_ended: the only session in the folder is dead
fresh; session 999999 $s1 src-a "$HOME/w"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ Sitzung beendet"* ]]

# test_pick: the newest live session inside the folder wins; dead ones and sibling folders do not
session $$ aaaaaaaa-2 src-b "$HOME/w/a" 1794700100000
session $PPID aaaaaaaa-3 src-c "$HOME/w/b" 1794700200000
session 999998 aaaaaaaa-4 src-d "$HOME/w/c" 1794700300000
session 999997 aaaaaaaa-5 src-e "$HOME/wx" 1794700400000
out=$(lage --dir "$HOME/w" --once);  [[ $out == "LAGE  w/b"* && $out != *"Sitzung beendet"* ]]
out=$(lage --dir "$HOME/w/c" --once);  [[ $out == "LAGE  w/c"* && $out == *"Sitzung beendet"* ]]
out=$(lage --dir "$HOME/wx/" --once);  [[ $out == "LAGE  wx"* ]]

# test_none: nobody in the folder; sessions elsewhere are still listed, without the footer (there is nothing to add an idea to)
fresh; out=$(lage --dir "$HOME/empty" --once);  [[ $out == "LAGE"*"14:12"$'\n'"kein Claude in empty" ]]
session $$ $s1 src-a "$HOME/w"
out=$(lage --dir "$HOME/empty" --once)
[[ $(sed -n 2p <<<"$out") == "kein Claude in empty" && $(sed -n 3p <<<"$out") == "! src-a wartet" && $out != *"i = Idee"* ]]   # src-a has no turn yet: it waits

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
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"▶ Protokoll nicht gefunden"* ]]

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
out=$(lage --dir "$HOME/w" --once --full)
[[ $out == *"FUNDE  2  (1 neu)"* && $out == *"NEU !  14:02 Admin-Login"* && $out == *"UNGEPRÜFT  0"* && $out == *"FÜR DICH  1  (1 neu)"* && $out == *"DEINE IDEEN  0 offen"* ]]
[[ $(grep '13:50 Port 22 offen' <<<"$out") == "    ·  13:50 Port 22 offen" ]]
[[ $out == *"NEU ·  14:09 Ist 10.10.10.7 im Scope?"* && $(grep -c NEU <<<"$out") -eq 2 ]]
# a rule below JETZT and one above the footer; every line fits
[[ $(grep -c '^──────' <<<"$out") -eq 2 && $(sed -n 3p <<<"$out") == ──────* && $(sed -n 4p <<<"$out") == "FUNDE  2  (1 neu)" && $(widest <<<"$out") -le 46 ]]
# no owner prompt in the transcript: nothing is NEU
fresh; session $$ $s1 src-a "$HOME/w"
printf '## Funde\n- 14:02 ! x\n' | board
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"FUNDE  1"$'\n'* && $out != *NEU* ]]

# test_peer_is_not_owner: helper mail and notifications do not move NEU
fresh; session $$ $s1 src-a "$HOME/w"
owner 14:02:40
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:11:00Z","origin":{"kind":"peer"},"message":{"content":"mail"}}'
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:11:30Z","origin":{"kind":"task-notification"},"message":{"content":"n"}}'
printf '## Funde\n- 14:05 spaeter\n- 14:01 frueher\n' | board
out=$(lage --dir "$HOME/w" --once --full)
[[ $out == *"FUNDE  2  (1 neu)"* && $out == *"NEU ·  14:05 spaeter"* && $out != *"NEU ·  14:01"* ]]
owner 14:11:50     # a real prompt does move it
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"FUNDE  2"$'\n'* && $out != *NEU* ]]

# test_older: what does not fit collapses; each section gets what is left of LINES - 1 after the rest, at least 1 line
fresh; session $$ $s1 src-a "$HOME/w"
{ echo '## Funde'; for m in 00 01 02 03 04 05 06; do echo "- 13:$m Fund $m"; done; } | board
out=$(LINES=24 lage --dir "$HOME/w" --once --full)
funde=$(sed -n '/^FUNDE/,/^UNGEPRÜFT/p' <<<"$out")
[[ $(grep -c 'Fund 0' <<<"$funde") -eq 2 && $funde == *"13:06 Fund 06"*"13:05 Fund 05"*$'\n+5 ältere\n'* && $funde != *"Fund 04"* ]]
out=$(LINES=11 lage --dir "$HOME/w" --once --full);  [[ $(grep -c 'Fund 0' <<<"$out") -eq 1 && $out == *$'\n+6 ältere\n'* ]]   # a small pane: one entry per section, the rest is cut
out=$(LINES=28 lage --dir "$HOME/w" --once --full);  [[ $(grep -c 'Fund 0' <<<"$out") -eq 3 && $out == *$'\n+4 ältere\n'* ]]
out=$(LINES=44 lage --dir "$HOME/w" --once --full);  [[ $(grep -c 'Fund 0' <<<"$out") -eq 7 && $out != *ältere* ]]

# test_height: main view and full view are never taller than LINES - 1 (the last newline would scroll the pane) nor wider than COLUMNS; header and JETZT stay on top
fresh; session $$ $s1 src-a "$HOME/w"
for m in 00 01 02 03 04 05 06 07 08 09; do entry $s1 "$(assistant 14:11:$m '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"Schritt '"$m"'"}}]')"; done
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
for i in 1 2 3 4 5 6; do live; session $pid "cap0000$i-1" "src-$i" "$HOME/empty"; done
{ for h in Funde Ungeprüft "Für dich"; do echo "## $h"; for m in 00 01 02 03 04; do echo "- 13:$m Eintrag $m"; done; done
  echo '## Deine Ideen'; for m in 00 01 02 03 04; do echo "- [ ] 13:$m Idee $m"; done; } | board
for C in 45 90; do for L in 60 40 27 20 11 8 5; do for v in "" --full; do
  out=$(COLUMNS=$C LINES=$L lage --dir "$HOME/w" --once $v)
  [[ $(wc -l <<<"$out") -le $((L - 1)) && $(widest <<<"$out") -le $C && $(sed -n 1p <<<"$out") == "LAGE  w"* && $out == *$'\n▶ x  seit 20 s'* ]] ||
    { echo "COLUMNS=$C LINES=$L $v: $(wc -l <<<"$out") lines" >&2; false; }
done; done; done
out=$(LINES=27 lage --dir "$HOME/w" --once)   # main view: who waits, the newest 8 steps, NEU, the keys; no board text
[[ $out == *$'\n\n▶ x  seit 20 s\n! src-1 wartet\n! src-2 wartet\n+4 weitere\n\nLOG\n'*$'\n\nNEU  0 Funde · 0 für dich · 5 Ideen\ni = Idee   f = alles' && $out != *──* ]]
[[ $(grep -c Schritt <<<"$out") -eq 7 && $out == *" 14:12 x"* && $out != *Eintrag* ]]   # 8 steps at most
out=$(LINES=8 lage --dir "$HOME/w" --once);  [[ $out == *"NEU  "* && $out != *LOG* ]]          # a small pane drops the log first
out=$(LINES=27 lage --dir "$HOME/w" --once --full)
[[ $out == *"! src-1 wartet"*"FUNDE"*"UNGEPRÜFT"*"FÜR DICH"*"DEINE IDEEN"*"i = Idee   f = zurück" && $out != *LOG* ]]

# test_old_day: an older day shows as DD.MM.
fresh; session $$ $s1 src-a "$HOME/w"
printf '## Funde\n- 2026-11-14 09:00 Gestern\n- 2026-11-15 09:00 Heute\n' | board
out=$(lage --dir "$HOME/w" --once --full)
[[ $out == *"·  09:00 Heute"*"·  14.11. Gestern"* && $out != *"15.11."* ]]    # newest first

# test_wrap: long entries wrap to the text column; one longer than its section is cut
fresh; session $$ $s1 src-a "$HOME/w"
long=$(printf 'wort%02d ' {1..16})
printf '## Funde\n- 14:02 ! %s\n- 13:00 kurz\n## Deine Ideen\n- [ ] %s\n' "$long" "$long" | board
out=$(LINES=47 lage --dir "$HOME/w" --once --full)
[[ $(widest <<<"$out") -le 46 && $out == *"    !  14:02 wort01 "* && $(grep -c '^             wort05 ' <<<"$out") -eq 2 && $(grep -c wort16 <<<"$out") -eq 2 ]]
[[ $out == *"·        [ ] wort01 "* ]]
out=$(lage --dir "$HOME/w" --once --full)
[[ $(widest <<<"$out") -le 46 && $out == *"wort01 "* && $out == *"…"$'\n'* && $out == *$'\n+1 ältere\n'* && $out != *wort16* ]]
# a dated row indents one column further
fresh; session $$ $s1 src-a "$HOME/w"
printf '## Funde\n- 2026-11-14 14:02 %s\n' "$long" | board
out=$(LINES=47 lage --dir "$HOME/w" --once --full)
[[ $out == *"·  14.11. wort01 "* && $out == *$'\n              wort05 '* ]]

# test_ideas: open ideas first, then done ones; ideas are never NEU
fresh; session $$ $s1 src-a "$HOME/w"
owner 12:00:00
printf '## Deine Ideen\n- [x] 14:11 robots lesen → nichts drin\n- [ ] 13:00 Cookie anschauen\n- Ohne Kästchen\n' | board
out=$(LINES=47 lage --dir "$HOME/w" --once --full)
[[ $out == *"DEINE IDEEN  2 offen"* && $out != *NEU* ]]
[[ $out == *"·  13:00 [ ] Cookie anschauen"*"[ ] Ohne Kästchen"*"·  14:11 [x] robots lesen → nichts drin"* ]]

# test_odd_board (Review Focus 4): hand-edited boards never crash and never invent NEU
fresh; session $$ $s1 src-a "$HOME/w"
owner 14:02:40
: | board
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"FUNDE  0"* && $out == *"DEINE IDEEN  0 offen"* ]]
printf '## Notizen\n- Fund im falschen Abschnitt\n' | board
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"FUNDE  0"* && $out != *falschen* ]]
printf '## Funde\n- kein Zeitstempel\n- 13:40 nur Uhrzeit\n- 25:99 kaputt\nfreie Zeile\n- \n-\n## Funde zwei\n- anderes\n' | board
out=$(LINES=47 lage --dir "$HOME/w" --once --full)
[[ $out == *"FUNDE  3"$'\n'* && $out != *NEU* && $out == *"·  13:40 nur Uhrzeit"*"kein Zeitstempel"*"25:99 kaputt"* && $out != *freie* && $out != *anderes* ]]
printf '## Funde\n- 14:30 bare Uhrzeit ist heute\n' | board
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"FUNDE  1  (1 neu)"* && $out == *"NEU ·  14:30 bare"* ]]
printf '## Funde\r\n- 14:30 ! mit CRLF\r\n' | board
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"NEU !  14:30 mit CRLF"* ]]
printf '## Funde\n- 14:30 x\xff\xfe\x1b[2Jy\n' | board
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"FUNDE  1"* && $out != *$'\e'* ]]
rm "$(bfile)"; mkdir "$(bfile)"                    # a directory where the board should be
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"FUNDE  0"* ]]
rc=0; lage --dir "$HOME/w" --idea 'x' 2>"$t/err" || rc=$?;  [[ $rc -eq 1 && $(<"$t/err") == "lage: "* ]]
rmdir "$(bfile)"; printf '## Funde\n- 0001-01-01 10:00 uralt\n- 14:30 jung\n' >"$(bfile)"
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"jung"*"01.01. uralt"* ]]       # a silly date neither crashes nor leads

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
plain = lage.board_lines(b, owner, 46, 2)
assert not any("\x1b" in x for x in plain), plain


class Tty(io.StringIO):
    def isatty(self):
        return True


sys.stdout = Tty()
lit = lage.board_lines(b, owner, 46, 2)
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


wait_for("i = Idee   f = alles".encode())
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

# test_f_key: key f switches to the whole board and back; what was new before is not NEU any more (needs a pty)
fresh; session $$ $s1 src-a "$HOME/w"; owner 14:00:00
printf '## Funde\n- 14:12 Fund nach dem Prompt\n' | board    # the same minute as the clock: seeing it must still count
python3 -B - "$here/lage.py" "$HOME/w" "$(bfile)" <<'EOF'
import json
import os
import pty
import select
import signal
import subprocess
import sys
import time
from pathlib import Path

prog, folder, board = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("python3", ["python3", prog, "--dir", folder])
seen = b""


def wait_for(text):
    global seen
    end = time.time() + 8
    while text.encode() not in seen and time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            seen += os.read(fd, 4096)
    assert text.encode() in seen, (text, seen[-300:])
    seen = b""


wait_for("NEU\x1b[0m  1 Fund ·")
wait_for("i = Idee   f = alles")
os.write(fd, b"f")
wait_for("FUNDE  1  (1 neu)")
wait_for("i = Idee   f = zurück")
os.write(fd, b"f")
wait_for("NEU\x1b[0m  0 Funde ·")  # seen in the full view: no longer new
with open(board, "a", encoding="utf-8") as f:
    f.write("- 14:12 noch einer\n")  # written later in the same minute: new
wait_for("NEU\x1b[0m  1 Fund ·")
# a second, newer session in the folder takes over; its board was never seen, even with the same text
sleeper = subprocess.Popen(["sleep", "60"])
home = Path.home()
(home / ".claude/sessions" / f"{sleeper.pid}.json").write_text(json.dumps(
    {"pid": sleeper.pid, "sessionId": "bbbbbbbb-2", "name": "src-b", "cwd": folder, "startedAt": 1794800000000, "status": "busy"}))
(home / ".claude/projects/p/bbbbbbbb-2.jsonl").write_text(
    '{"type":"user","timestamp":"2026-11-15T14:00:00Z","origin":{"kind":"human"},"message":{"content":"los"}}\n')
(home / ".local/state/lage/bbbbbbbb-2.md").write_text("## Funde\n- 14:12 Fund nach dem Prompt\n")
wait_for("NEU\x1b[0m  1 Fund ·")
sleeper.kill()
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
assert tr.last is None, tr.last
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

# test_wartet: a line per other waiting session, with its tab title and what it waits for; the followed one never; only the first line of the text
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
live; session $pid bbbbbbbb-2 src-c8 "$HOME/empty"
entry bbbbbbbb-2 '{"type":"ai-title","aiTitle":"Bot-Menü","sessionId":"bbbbbbbb-2"}'
entry bbbbbbbb-2 "$(assistant 14:12:00 '"end_turn"' '[{"type":"text","text":"Soll ich es ausrollen, oder erst morgen?\nzweite Zeile"}]')"
out=$(COLUMNS=80 lage --dir "$HOME/w" --once)
[[ $out == *$'\n! Bot-Menü wartet: Soll ich es ausrollen, oder erst morgen?\n'* && $out != *"zweite Zeile"* && $out != *src-c8* && $(grep -c ' wartet' <<<"$out") -eq 1 ]]
# a line wider than the window is cut with an ellipsis, never wrapped
out=$(lage --dir "$HOME/w" --once);  line=$(grep Bot-Menü <<<"$out")
[[ ${#line} -eq 46 && $line == *"…" && $line == "! Bot-Menü wartet: Soll ich es ausrollen, ode"* ]]
# the followed session waits too: that shows in its ▶ line, never as a waiting line
entry $s1 "$(assistant 14:12:10 '"end_turn"' '[{"type":"text","text":"Fertig, ok?"}]')"
out=$(COLUMNS=60 lage --dir "$HOME/w" --once)
[[ $(grep -c '^! ' <<<"$out") -eq 1 && $out == *"▶ wartet auf dich"* && $out != *"src-a wartet"* ]]
# helpers running: it does not wait, no line
sub=$HOME/.claude/projects/p/bbbbbbbb-2/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-a1.meta.json"; echo '{}' >"$sub/agent-a1.jsonl"; touch -d 2026-11-15T14:10:00Z "$sub/agent-a1.jsonl"
out=$(COLUMNS=60 lage --dir "$HOME/w" --once);  [[ $out != *"Bot-Menü"* ]]

# test_wartet_answered: a question the owner has answered is not shown as waited on again
fresh; session $$ $s1 src-a "$HOME/w"
live; session $pid bbbbbbbb-2 src-b "$HOME/empty"
entry bbbbbbbb-2 "$(assistant 14:11:00 '"end_turn"' '[{"type":"text","text":"Soll ich ausrollen?"}]')"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"! src-b wartet: Soll ich ausrollen?"* ]]
entry bbbbbbbb-2 '{"type":"user","timestamp":"2026-11-15T14:12:00Z","origin":{"kind":"human"},"message":{"content":"los"}}'
entry bbbbbbbb-2 "$(assistant 14:12:10 '"end_turn"' '[]')"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"! src-b wartet"* && $out != *ausrollen* ]]

# test_wartet_names: a /rename title beats Claude's title, the title beats the name; no title and no name → first 6 characters of the session id; title and name are cut; control characters never reach the terminal
fresh; session $$ $s1 src-a "$HOME/w"
live; echo '{"pid":'"$pid"',"sessionId":"deadbe12-3456","cwd":"/x","startedAt":1794700000000}' >"$HOME/.claude/sessions/$pid.json"
live; session $pid cafe0000-1 "" "$HOME/empty"
entry cafe0000-1 '{"type":"ai-title","aiTitle":"Dies ist ein sehr langer Titel","sessionId":"cafe0000-1"}'
live; session $pid evil0000-1 '\u001b[31mevil name that is long' "$HOME/empty"
entry evil0000-1 '{"type":"ai-title","aiTitle":"a\u001b[0mb\u009bc","sessionId":"evil0000-1"}'
out=$(COLUMNS=80 lage --dir "$HOME/w" --once)
[[ $out == *"! deadbe wartet"* && $out == *"! Dies ist ein sehr… wartet"* && $out == *"! a?[0mb?c wartet"* && $out != *cafe00* ]]
[[ $out != *$'\x1b'* && $out != *$'\xc2\x9b'* && $(widest <<<"$out") -le 80 ]]
fresh; session $$ $s1 src-a "$HOME/w"
live; session $pid evil0000-2 '\u001b[31mevil name that is long' "$HOME/empty"
live; session $pid renamed0-1 src-r "$HOME/empty"
entry renamed0-1 '{"type":"ai-title","aiTitle":"Claude-Titel","sessionId":"renamed0-1"}'
entry renamed0-1 '{"type":"custom-title","customTitle":"Mein Titel","sessionId":"renamed0-1"}'
entry renamed0-1 '{"type":"ai-title","aiTitle":"Neuer Claude-Titel","sessionId":"renamed0-1"}'
out=$(COLUMNS=80 lage --dir "$HOME/w" --once)
[[ $out == *"! ?[31mevil n… wartet"* && $out == *"! Mein Titel wartet"* && $out != *Claude-Titel* && $out != *src-r* && $out != *$'\x1b'* ]]

# test_dead_hidden: a session whose pid is gone has no line
fresh; session $$ $s1 src-a "$HOME/w"
session 999999 dddddddd-4 src-dead "$HOME/empty"
out=$(lage --dir "$HOME/w" --once);  [[ $out != *src-dead* ]]
fresh; session 999999 dddddddd-4 src-dead "$HOME/w"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *"Sitzung beendet"* && $out != *src-dead* ]]

# test_wartet_cap: more than 3 waiting → 2 lines and "+N weitere", by name; no line wider than the window
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
for i in 1 2 3 4 5; do live; session $pid "cap0000$i-1" "src-$i" "$HOME/empty"; done
out=$(lage --dir "$HOME/w" --once)
[[ $(grep -c '^! ' <<<"$out") -eq 2 && $out == *$'! src-1 wartet\n! src-2 wartet\n+3 weitere\n'* && $(widest <<<"$out") -le 46 ]]
# exactly 3: all three, no "+N weitere"
fresh; session $$ $s1 src-a "$HOME/w"
for i in 1 2 3; do live; session $pid "cap0000$i-1" "src-$i" "$HOME/empty"; done
out=$(lage --dir "$HOME/w" --once);  [[ $(grep -c '^! ' <<<"$out") -eq 3 && $out != *weitere* ]]

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
first = lage.wartet_lines("aaaaaaaa-1", 60)
assert first == [], first  # src-b works
tr = lage.transcripts["bbbbbbbb-2"]
assert tr.pos == f.stat().st_size
with f.open("a") as h:
    h.write('{"type":"ai-title","aiTitle":"Neu","sessionId":"bbbbbbbb-2"}\n')
    h.write(entry % ("end_turn", '{"type":"text","text":"Fertig?"}'))
second = lage.wartet_lines("aaaaaaaa-1", 60)
assert lage.transcripts["bbbbbbbb-2"] is tr and tr.pos == f.stat().st_size
assert second == ["! Neu wartet: Fertig?"], second  # the title from the new bytes
before = tr.pos
lage.wartet_lines("aaaaaaaa-1", 60)
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

# test_hook_idea_again: the same text typed again later is a new idea, even when the first one is ticked off
fresh; session $$ $s1 src-a "$HOME/w"
lage --dir "$HOME/w" --idea 'Cookie'
[[ $(hook PostToolUse $s1 | context) == 'Neue Idee von vino: Cookie' ]]
sed -i 's/\[ \] 2026-11-15 14:12/[x] 2026-11-15 14:12/' "$(bfile)"
[[ -z $(hook PostToolUse $s1) ]]
LAGE_NOW=2026-11-15T14:20:00Z lage --dir "$HOME/w" --idea 'Cookie'
[[ $(hook PostToolUse $s1 | context) == 'Neue Idee von vino: Cookie' && -z $(hook PostToolUse $s1) ]]

# test_hook_start_with_ideas: SessionStart gives the path, then the open ideas, one per line
fresh; session $$ $s1 src-a "$HOME/w"
lage --dir "$HOME/w" --idea 'eins'; lage --dir "$HOME/w" --idea 'zwei'
[[ $(hook SessionStart $s1 | context) == "Lage-Board: $HOME/.local/state/lage/$s1.md"$'\nNeue Idee von vino: eins\nNeue Idee von vino: zwei' ]]
[[ -z $(hook PostToolUse $s1) ]]
# a session start also follows compaction, resume and clear, which may have lost what was told: the open ideas are told again, once
[[ $(hook SessionStart $s1 | context) == "Lage-Board: $HOME/.local/state/lage/$s1.md"$'\nNeue Idee von vino: eins\nNeue Idee von vino: zwei' ]]
[[ -z $(hook PostToolUse $s1) && -z $(hook UserPromptSubmit $s1) ]]

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
[[ $out == "LAGE  w"*"14:12"* && $out == *"▶ prüft die Webseite"* && $out != *"kein Claude"* ]]
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
rc=0; out=$(lage --once) || rc=$?; [[ $rc -eq 0 && $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" && $(sed -n 1p <<<"$out") == "LAGE"*"14:12" ]]
rc=0; out=$(lage --idea x 2>&1) || rc=$?; [[ $rc -eq 1 && $out == "lage: kein Claude im Hauptfenster" ]]
rc=0; out=$(PATH=$t/none "$py" "$here/lage.py" --once) || rc=$?  # test_no_hyprctl
[[ $rc -eq 0 && $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" ]]
CLIENTS='Hyprland is not running' out=$(lage --once); [[ $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" ]]
clients "$(cl 999999 kitty 3 0 0)"; out=$(lage --once); [[ $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" ]]  # no own window
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $pid kitty 3 0 0 false true)" "$(cl $pid kitty 4 0 0)"
out=$(lage --once); [[ $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" ]]                                # no candidate

# test_master_none_lists_sessions: no Claude in the master window, yet the other sessions are listed
fresh; live; clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $pid kitty 3 0 0)"
session $$ $s1 src-a "$HOME/w"
out=$(lage --once);  [[ $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" && $(sed -n 3p <<<"$out") == "! src-a wartet" ]]

# test_master_switch: the master tab shows something else while the session lives: no "Sitzung beendet"; only a gone session is ended
fresh; window "$t/bin/claude"; session $child $s1 src-a "$HOME/w"; session 999999 dddddddd-4 src-dead "$HOME/w"; live
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $wrapper kitty 3 0 0)"; in_claude=$CLIENTS
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $pid kitty 3 0 0)"; in_browser=$CLIENTS
python3 -B - "$here" "$in_claude" "$in_browser" "$child" <<'EOF2'
import os
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import lage

in_claude, in_browser, child = sys.argv[2:]
os.environ["CLIENTS"] = in_claude
session, ended = lage.master_session(None)
assert session["sessionId"] == "aaaaaaaa-1" and not ended, (session, ended)
os.environ["CLIENTS"] = in_browser
assert lage.master_session(session) == (None, False)  # alive: only the view changed
dead = next(s for s in lage.sessions() if s["sessionId"] == "dddddddd-4")
assert lage.master_session(dead) == (dead, True)  # its process is gone
(Path.home() / f".claude/sessions/{child}.json").unlink()
assert lage.master_session(session) == (session, True)  # its file is gone
EOF2

# test_tmux: the kitty runs a tmux client; its pane holds the claude
fresh; window "$t/bin/tmux" client; w1=$wrapper; tm=$child
window "$t/bin/claude"; session $child $s1 src-a "$HOME/w"; cc=$child   # outside the first window
probe $w1; [[ $rc -eq 1 ]]                                              # list-clients names no pane
TMUX_CLIENTS="$tm $cc" probe $w1; [[ $rc -eq 0 ]]
TMUX_CLIENTS="$tm $pid" probe $w1; [[ $rc -eq 1 ]]                       # a pane without claude
TMUX_CLIENTS="$((tm + 1)) $cc" probe $w1; [[ $rc -eq 1 ]]                # only the client below this window counts
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $w1 kitty 3 0 0)"
[[ $(TMUX_CLIENTS="$tm $cc" lage --once) == "LAGE  w"* ]]
# no tmux on PATH: the client's own binary answers, but lage runs it only when it is a tmux from the Nix store.
# Here it is a copy of sh named tmux outside the store (it would run ./list-clients): never run, so no pane is found.
cp "$(readlink -f /bin/sh)" "$t/exe/tmux"; printf 'touch ran\nprintf "%%s\\n" "$TMUX_CLIENTS"\n' >"$t/exe/list-clients"
window "$t/exe/tmux" -c 'sleep 60; :'; tm=$child
rc=0; out=$(cd "$t/exe" && TMUX_CLIENTS="$tm $cc" PATH=$t/none "$py" "$here/lage.py" --probe $wrapper 2>&1) || rc=$?
[[ $rc -eq 1 && -z $out && ! -e $t/exe/ran ]]
python3 -B - "$here" <<'EOF2'
import os
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import lage

store = "/nix/store/0123abc-tmux-3.8/bin/tmux"  # the store path need not exist: it cannot be faked outside the store
assert lage.store_tmux(store) == store
for bad in ("/nix/store/0123abc-tmux-3.8/bin/sh", "/nix/store/0123abc-tmux-3.8/bin/tmux2", "/nix/storex/tmux", "/tmp/nix/store/x/tmux", "/nix/store/../tmp/tmux", "/proc/self/exe"):
    assert lage.store_tmux(bad) is None, bad
link = Path.home() / "tmux"
link.symlink_to(store)
assert lage.store_tmux(str(link)) == store  # the resolved path is what gets run
link.unlink()
link.symlink_to("/tmp/other/tmux")
assert lage.store_tmux(str(link)) is None
EOF2

# test_master_ended: the session goes away; the board stays with "Sitzung beendet" until another session turns up
fresh; window "$t/bin/claude"; session $child $s1 src-a "$HOME/w"
board <<'EOF2'
## Funde
- 14:00 ! ein Fund
EOF2
clients "$(cl $$ cockpit-log 3 1700 0)" "$(cl $wrapper kitty 3 0 0)"
poll() { local i; for i in {1..150}; do grep -q "$1" "$t/out" && return 0; sleep 0.1; done; die "never printed: $1"; } # poll <text>: wait for the loop to print it
"$py" "$here/lage.py" --full </dev/null >"$t/out" 2>&1 & sl+=($!)
poll '▶ wartet auf dich'
rm "$HOME/.claude/sessions/$child.json"
poll '▶ Sitzung beendet'
[[ $(grep -c 'ein Fund' "$t/out") -ge 2 && -z $(grep 'kein Claude' "$t/out" || true) ]]     # the board is kept, no "kein Claude"
session $child $s1 src-a "$HOME/w"
before=$(grep -c '▶ wartet auf dich' "$t/out"); for i in {1..150}; do [[ $(grep -c '▶ wartet auf dich' "$t/out") -gt $before ]] && break; sleep 0.1; done
[[ $(grep -c '▶ wartet auf dich' "$t/out") -gt $before ]]                              # found again

# lage bar: counts like the pane; helpers count as busy; dead pids do not count
fresh; live; p1=$pid; session $p1 $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}]')"
out=$(lage bar); jq -e '.text == "● 1" and .class == "busy"' <<<"$out"
status $p1 waiting "Erlaubnis"; out=$(lage bar); jq -e '.text == "▲ 1" and .class == "waiting"' <<<"$out"
jq -e '.tooltip | test("^▲ src-a")' <<<"$out"
status $p1 idle; out=$(lage bar); jq -e '.text == "▲ 1"' <<<"$out"            # idle = wartet, like the pane
sub=$HOME/.claude/projects/p/$s1/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-1.meta.json"; : >"$sub/agent-1.jsonl"
out=$(lage bar); jq -e '.text == "● 1" and .class == "busy"' <<<"$out"        # helfer = busy
live; session $pid bbbbbbbb-2 src-b "$HOME/w"; status $pid waiting
out=$(lage bar); jq -e '.text == "● 1 ▲ 1" and .class == "waiting"' <<<"$out"
fresh; session 999999 $s1 src-a "$HOME/w"; jq -e '.text == ""' <<<"$(lage bar)"  # dead pid: hidden
# tail read: 1 MiB of filler before the last entry classifies like a full read; no settled entry in the tail falls back
filler() { # filler <sid>: 1 MiB of progress lines, the last one ended (fold leaves it open and the next entry would join it)
  head -c 1048576 /dev/zero | tr '\0' 'x' | fold -w 1000 | sed 's/^/{"type":"progress","d":"/; s/$/"}/' >>"$HOME/.claude/projects/p/$1.jsonl"
  echo >>"$HOME/.claude/projects/p/$1.jsonl"
}
tailed() { # tailed <sid>: true when a tail read of the transcript did not see the owner prompt at its start (the tail was kept)
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import lage; t = lage.Transcript(sys.argv[2]); t.tail(); print(t.owner_ts is None)' "$here" "$1"
}
fresh; live; session $pid $s1 src-a "$HOME/w"
owner 14:00
entry $s1 "$(assistant 14:11:00 '"end_turn"' '[{"type":"text","text":"fertig"}]')"
filler $s1
jq -e '.text == "▲ 1"' <<<"$(lage bar)"                                       # fallback found the end_turn
[[ $(tailed $s1) == False ]]                                                   # ... by reading the whole file
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}]')"
jq -e '.text == "● 1"' <<<"$(lage bar)"                                       # tail sees the newest entry
[[ $(tailed $s1) == True ]]                                                    # ... and did not read the start
status $pid ""; jq -e '.text == "● 1"' <<<"$(lage bar)"                       # no status: the tail settles on the tool call too
# helpers on the tail path: end_turn inside the window, a helper still running
fresh; live; session $pid $s1 src-a "$HOME/w"
owner 14:00; filler $s1
entry $s1 "$(assistant 14:11:00 '"end_turn"' '[{"type":"text","text":"fertig"}]')"
jq -e '.text == "▲ 1"' <<<"$(lage bar)"
[[ $(tailed $s1) == True ]]
sub=$HOME/.claude/projects/p/$s1/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-1.meta.json"; : >"$sub/agent-1.jsonl"
jq -e '.text == "● 1" and (.tooltip | test("Helfer arbeiten"))' <<<"$(lage bar)"
# no status: the settling tool call is outside the window, only an unsettled owner prompt inside: falls back, like a full read
fresh; live; session $pid $s1 src-a "$HOME/w"; status $pid ""
entry $s1 "$(assistant 14:11:00 '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}]')"
filler $s1
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:00Z","message":{"content":"hallo"}}'
jq -e '.text == "● 1" and (.tooltip | test("liest x"))' <<<"$(lage bar)"

# lage bar --focus: the window of the session that waits longest, else of the one busy longest. Fake windows as above;
# a second hyprctl stub (first on PATH for these calls) also records the dispatches.
mkdir -p "$t/fbin"
cat >"$t/fbin/hyprctl" <<'FAKE'
#!/bin/sh
[ "$1" = clients ] && { printf '%s\n' "$CLIENTS"; exit 0; }
echo "$*" >>"$DISPATCH"
FAKE
chmod +x "$t/fbin/hyprctl"
export DISPATCH=$t/dispatch
client() { cl "$2" kitty 3 0 0 | jq -c --arg a "$1" '. + {address: $a}'; } # client <addr> <pid>
plain() { live; cls+=("$(client "$1" $pid)"); clients "${cls[@]}"; }       # plain <addr>: a window without claude
win() { # win <addr> <sid> <status> <time>: a window with a claude session whose newest entry (a tool call) is at <time>
  window "$t/bin/claude"
  session $child "$2" src-$1 "$HOME/w"; status $child "$3"
  entry "$2" "$(assistant "$4" '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}]')"
  cls+=("$(client "$1" $wrapper)"); clients "${cls[@]}"
}
focus() { : >"$DISPATCH"; rc=0; PATH=$t/fbin:$PATH lage bar --focus || rc=$?; } # exit code in $rc, the dispatches in $DISPATCH
fresh; cls=(); plain 0xother; win 0xwin $s1 waiting 14:00:00
focus; [[ $rc == 0 && $(<"$DISPATCH") == 'dispatch hl.dsp.focus({ window = "address:0xwin" })' ]]   # the plain window is skipped
fresh; cls=(); plain 0xother; focus; [[ $rc == 1 && ! -s $DISPATCH ]]          # no session: exit 1, no dispatch
fresh; session $$ $s1 src-a "$HOME/w"; status $$ waiting                       # a waiting session in no window
focus; [[ $rc == 1 && ! -s $DISPATCH ]]
CLIENTS=garbage focus; [[ $rc == 1 && ! -s $DISPATCH ]]                         # hyprctl output is no JSON
# several sessions: waiting beats busy (even a longer-busy one), the longest-waiting of them wins; none waiting: the longest-busy
fresh; cls=(); win 0xbusy bbbbbbbb-1 busy 14:00:00; win 0xnew bbbbbbbb-2 waiting 14:10:00; win 0xold bbbbbbbb-3 waiting 14:05:00
focus; [[ $rc == 0 && $(<"$DISPATCH") == *'address:0xold'* ]]
fresh; cls=(); win 0xnew bbbbbbbb-1 busy 14:10:00; win 0xold bbbbbbbb-2 busy 14:05:00
focus; [[ $rc == 0 && $(<"$DISPATCH") == *'address:0xold'* ]]

echo ok
