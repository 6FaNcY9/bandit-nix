#!/usr/bin/env bash
# Test for tools/lage.py with a fake HOME, fixture sessions and transcripts, a fixed clock.
# Run: tools/lage.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); sl=(); trap 'rm -rf "$t"; ((${#sl[@]})) && kill -- "${sl[@]}" 2>/dev/null || true' EXIT
export XDG_RUNTIME_DIR=$t/run; mkdir -p "$XDG_RUNTIME_DIR"
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
  out=$(lage --dir "$HOME/w" --once --full)
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
r46=$(printf '─%.0s' {1..46})  # one whole rule at the default 46 columns

# test_tool_use
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"prüft die Webseite"}}]')"
entry $s1 '{"type":"mode"}'                                  # no timestamp: skipped
out=$(lage --dir "$HOME/w" --once --full)
[[ $out == *"▶ prüft die Webseite  seit 20 s"* && $out == *"14:12"* ]]
first=$(head -n 1 <<<"$out")
[[ $first == "LAGE  w"*"14:12" && ${#first} -eq 46 ]]    # right-aligned to the window width

# test_partial_line: garbage and a half-written line change nothing
before=$out
echo garbage >>"$HOME/.claude/projects/p/$s1.jsonl"
echo '{"type":"assistant", garbage' >>"$HOME/.claude/projects/p/$s1.jsonl"
printf '{"type":"assistant","timest' >>"$HOME/.claude/projects/p/$s1.jsonl"
[[ $(lage --dir "$HOME/w" --once --full) == "$before" ]]

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
out=$(lage --dir "$HOME/w" --once --full)
[[ $out == *"liest second"* && $out != *first* ]]

# test_end_turn
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"end_turn"' '[{"type":"text","text":"fertig"}]')"
out=$(lage --dir "$HOME/w" --once --full)
[[ $out == *"▶ wartet auf dich"* && $out == *"seit 20 s"* ]]

# test_helpers: a helper without "finished" and a recently written log keeps the session busy
sub=$HOME/.claude/projects/p/$s1/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-a1.meta.json"; echo '{}' >"$sub/agent-a1.jsonl"
touch -d 2026-11-15T14:10:00Z "$sub/agent-a1.jsonl"
out=$(lage --dir "$HOME/w" --once --full)
[[ $out == *"Helfer arbeiten (1)"* && $out == *"seit 20 s"* && $out != *"wartet auf dich"* ]]
echo '{"finished":true}' >"$sub/agent-a1.meta.json"
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"wartet auf dich"* && $out != *"Helfer arbeiten"* ]]
echo '{}' >"$sub/agent-a1.meta.json"; touch -d 2026-11-15T13:00:00Z "$sub/agent-a1.jsonl"   # stale log: gave up
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"wartet auf dich"* ]]

# test_thinking: owner prompt, tool result, text before a tool call
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:00Z","origin":{"kind":"human"},"message":{"content":"los"}}'
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ denkt nach"* && $out == *"seit 20 s"* ]]
entry $s1 "$(assistant 14:12:05 null '[{"type":"text","text":"ich schaue nach"}]')"
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ denkt nach"* && $out == *"seit 15 s"* ]]
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:10Z","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ denkt nach"* && $out == *"seit 10 s"* ]]

# test_status: the status in the session file beats the transcript where the transcript cannot know
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
status $$ waiting 'dialog open'                                    # a permission prompt or a question: the last entry is still the tool call
out=$(COLUMNS=60 lage --dir "$HOME/w" --once --full)
[[ $out == *"▶ wartet auf dich: dialog open  seit 20 s"* && $out != *" wartet: "* && $out != *"▶ x"* ]]   # the followed session is never in the waiting lines
status $$ waiting $'sandbox\e[2J request'                          # outside text: control characters never reach the terminal
out=$(COLUMNS=60 lage --dir "$HOME/w" --once --full);  [[ $out == *"sandbox?[2J request"* && $out != *$'\e'* ]]
status $$ waiting
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ wartet auf dich  seit 20 s"* ]]
status $$ idle                                                     # idle while the transcript still says tool
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ wartet auf dich"* && $out != *"▶ x"* ]]
sub=$HOME/.claude/projects/p/$s1/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-a1.meta.json"; echo '{}' >"$sub/agent-a1.jsonl"; touch -d 2026-11-15T14:10:00Z "$sub/agent-a1.jsonl"
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ Helfer arbeiten (1)"* && $out != *"wartet auf dich"* ]]
rm -r "$sub"
for st in busy shell bogus; do                                     # busy, shell and unknown: the transcript decides
  status $$ $st; out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ x  seit 20 s"* ]]
done
entry $s1 "$(assistant 14:12:10 '"end_turn"' '[{"type":"text","text":"fertig"}]')"
status $$ busy; out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ wartet auf dich  seit 10 s"* ]]
fresh; session $$ $s1 src-a "$HOME/w"; owner 14:12:00; status $$ idle   # idle after an owner prompt: nothing runs
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ wartet auf dich"* && $out != *"denkt nach"* ]]
# no status at all (older Claude Code): a user entry that is no turn leaves the state alone; an interrupt marker ends the turn
fresh; session $$ $s1 src-a "$HOME/w"; status $$ ""
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:10Z","message":{"content":"<local-command-stdout>ok</local-command-stdout>"}}'
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ x  seit 20 s"* ]]
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:10Z","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}'
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ wartet auf dich  seit 10 s"* ]]
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:15Z","origin":{"kind":"human"},"message":{"content":"weiter"}}'
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ denkt nach  seit 5 s"* ]]
fresh; session $$ $s1 src-a "$HOME/w"                                 # with a status the same entries replace the state, as before
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
entry $s1 '{"type":"user","timestamp":"2026-11-15T14:12:10Z","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}'
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ denkt nach  seit 10 s"* ]]

# test_age: seconds, minutes, hours
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:09:20 '"end_turn"' '[]')"
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"seit 3 min"* ]]
entry $s1 "$(assistant 12:12:00 '"end_turn"' '[]')"
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"seit 2 h"* ]]

# test_tool_names: names a person can read: memory tools, web tools, the board file
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

# test_overview_rows: one line per live session, by start: works (with its step), waits (only a status waiting),
# helpers, rests (idle, with its age); idle never reads "wartet auf dich"; a dead session has no line
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *$'\n ● src-a  arbeitet  x\n'* ]]
status $$ idle; out=$(lage --dir "$HOME/w" --once)
[[ $out == *$'\n ○ src-a  ruht  20 s\n'* && $out != *"wartet auf dich"* ]]
status $$ waiting 'Erlaubnis'; out=$(lage --dir "$HOME/w" --once);  [[ $out == *$'\n ▲ src-a  wartet auf dich  20 s\n'* ]]
status $$ idle; sub=$HOME/.claude/projects/p/$s1/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-a1.meta.json"; echo '{}' >"$sub/agent-a1.jsonl"; touch -d 2026-11-15T14:10:00Z "$sub/agent-a1.jsonl"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *$'\n ● src-a  Helfer arbeiten (1)\n'* ]]
rm -r "$sub"
live; session $pid bbbbbbbb-2 src-b "$HOME/empty" 1794700100000   # started later: below src-a; busy without a turn yet
session 999999 dddddddd-4 src-dead "$HOME/empty"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *$'\n ○ src-a  ruht  20 s\n ● src-b  arbeitet\n'* && $out != *src-dead* ]]
fresh; out=$(lage --dir "$HOME/empty" --once);  [[ $out == *$'\n keine Sitzung\n'* ]]

# test_du: the owner's next steps in a fixed order: liefern's queue, sessions waiting for him (longest first), open !
# lines under Für dich on the boards of live sessions (newest first, cut at ": " or ". "); at most 3, the rest counted
fresh; session $$ $s1 src-a "$HOME/w"
out=$(lage --dir "$HOME/w" --once);  [[ $(sed -n 2p <<<"$out") == " DU  nichts offen" ]]
board <<'EOF'
## Funde
- 14:01 ! ein Fund ist kein Schritt
## Für dich
- 14:05 ! Brief an die Behörde: Name fehlt
- 14:06 ! Mrija. Passwort ändern
- 14:07 ! alt → erledigt
- 14:08 normal
EOF
out=$(lage --dir "$HOME/w" --once)
[[ $out == *$'\n DU\n 1  Mrija. Passwort ändern\n 2  Brief an die Behörde\n─'* && $out != *alt* && $out != *normal* ]]
[[ $out == *$'\n NEU\n 14:01  src-a\n    ein Fund ist kein Schritt\n─'* ]]   # a Fund is no step: it shows under NEU
mkdir -p "$HOME/.local/state/liefern/warten"; touch "$HOME/.local/state/liefern/warten/1.eintrag"
out=$(lage --dir "$HOME/w" --once);  [[ $out == *$'\n DU\n 1  liefern · 1 wartet\n 2  Mrija. Passwort ändern\n'* ]]
touch "$HOME/.local/state/liefern/warten/2.eintrag"
live; session $pid bbbbbbbb-2 src-b "$HOME/empty"; status $pid waiting 'Erlaubnis für Bash'
live; session $pid bbbbbbbb-3 src-c "$HOME/empty"; status $pid waiting
entry bbbbbbbb-2 "$(assistant 14:11:00 '"tool_use"' '[]')"; entry bbbbbbbb-3 "$(assistant 14:10:00 '"tool_use"' '[]')"
out=$(COLUMNS=60 lage --dir "$HOME/w" --once)
[[ $out == *$'\n DU\n 1  liefern · 2 warten\n 2  ▲ src-c wartet auf dich\n 3  ▲ src-b wartet auf dich: Erlaubnis für Bash\n    +2 weitere\n─'* ]]
# two live sessions in one lab folder share a board: its ! line counts once (Review Focus 1)
fresh; session $$ $s1 src-a "$HOME/src/sec/ctf/box1"; live; session $pid bbbbbbbb-2 src-b "$HOME/src/sec/ctf/box1/sub"
mkdir -p "$HOME/src/sec/ctf/box1/.claude"; printf '## Für dich\n- 14:05 ! Flag prüfen\n' >"$HOME/src/sec/ctf/box1/.claude/lage.md"
out=$(lage --dir "$HOME/src/sec/ctf/box1" --once);  [[ $(grep -c 'Flag prüfen' <<<"$out") -eq 1 ]]
# a step without ": " or ". " that is wider than the pane is cut with …, never wrapped (Review Focus 2)
fresh; session $$ $s1 src-a "$HOME/w"
printf '## Für dich\n- 14:05 ! %s\n' "$(printf 'wort%02d ' {1..20})" | board
out=$(lage --dir "$HOME/w" --once);  line=$(grep '^ 1  wort01' <<<"$out")
[[ ${#line} -eq 46 && $line == *"…" && $(widest <<<"$out") -le 46 && $(grep -c wort02 <<<"$out") -eq 1 ]]

# test_cut: a step is cut at the first ": " or ". " only when the part before it has at least 2 words (owner,
# 2026-11-19): a one-word head ("Handy", "Dr", "z") says too little, so the whole text stays (cut to the pane with …)
fresh; session $$ $s1 src-a "$HOME/w"
printf '## Für dich\n- 14:01 ! Brief an die Behörde: Name fehlt\n- 14:02 ! Handy: Samsung zurücksetzen\n- 14:03 ! Dr. Maier anrufen\n' | board
out=$(lage --dir "$HOME/w" --once)
[[ $out == *$'\n DU\n 1  Dr. Maier anrufen\n 2  Handy: Samsung zurücksetzen\n 3  Brief an die Behörde\n'* ]]

# test_news: NEU shows the newest Fund of each live session (by time, not by place on the board) in the order of the
# rows, its time and label, below it the text cut to the pane; another day shows DD.MM.; a shared lab board counts once;
# a session without Funde has no entry
fresh; session $$ $s1 src-a "$HOME/w"
printf '## Funde\n- 13:50 ! alter Fund\n- 14:09 neuer Fund\n## Für dich\n- 14:11 ! kein Fund\n' | board
live; session $pid bbbbbbbb-2 src-b "$HOME/empty" 1794700100000   # started later, no board: no entry
out=$(lage --dir "$HOME/w" --once)
[[ $out == *$'\n NEU\n 14:09  src-a\n    neuer Fund\n─'* && $out != *"alter Fund"* && $out != *$'src-b\n    '* ]]
live; session $pid cccccccc-3 src-c "$HOME/empty" 1794700200000
printf '## Funde\n- 2026-11-14 09:00 von gestern %s\n' "$(printf 'wort%02d ' {1..12})" >"$HOME/.local/state/lage/cccccccc-3.md"
out=$(lage --dir "$HOME/w" --once);  line=$(grep '^    von gestern' <<<"$out")
[[ $out == *$'\n NEU\n 14:09  src-a\n    neuer Fund\n 14.11.  src-c\n    von gestern'* && ${#line} -eq 46 && $line == *"…" ]]
fresh; session $$ $s1 src-a "$HOME/src/sec/ctf/box1"; live; session $pid bbbbbbbb-2 src-b "$HOME/src/sec/ctf/box1/sub"
mkdir -p "$HOME/src/sec/ctf/box1/.claude"; printf '## Funde\n- 14:05 Port 22 offen\n' >"$HOME/src/sec/ctf/box1/.claude/lage.md"
out=$(lage --dir "$HOME/src/sec/ctf/box1" --once);  [[ $(grep -c 'Port 22 offen' <<<"$out") -eq 1 && $out == *$'\n 14:05  src-a\n'* ]]

# test_delivered: GELIEFERT heute counts today's done liefern entries and shows the newest 3 with their time and the
# owner's sentence; yesterday's entries and the moved scripts themselves do not count
fresh; session $$ $s1 src-a "$HOME/w"
d=$HOME/.local/state/liefern/fertig; mkdir -p "$d"
for x in 0811-a 0956-b 1037-c 1047-d; do printf '/x/%s.sh\nSatz %s\n' "${x#*-}" "${x#*-}" >"$d/2026-11-15-$x.sh.eintrag"; done
printf '/x/y.sh\nSatz gestern\n' >"$d/2026-11-14-2300-y.sh.eintrag"; : >"$d/2026-11-15-1047-d.sh"
out=$(lage --dir "$HOME/w" --once)
[[ $out == *$'\n GELIEFERT heute (4)\n 10:47  Satz d\n 10:37  Satz c\n 09:56  Satz b\n─'* && $out != *"Satz a"* && $out != *gestern* ]]
# the order of the blocks; a small pane keeps today's frame first: NEU in whole pairs, GELIEFERT only with a row
printf '## Funde\n- 14:09 neuer Fund\n' | board
out=$(LINES=30 lage --dir "$HOME/w" --once)
[[ $out == *$'\n ● src-a  arbeitet\n'"$r46"$'\n NEU\n 14:09  src-a\n    neuer Fund\n'"$r46"$'\n GELIEFERT heute (4)\n'*$'\n'"$r46"$'\n f alles   i Idee   ⏎ zur Sitzung' ]]
out=$(LINES=12 lage --dir "$HOME/w" --once);  [[ $out == *$'\n    neuer Fund\n'"$r46"$'\n f alles'* && $out != *GELIEFERT* ]]
out=$(LINES=9 lage --dir "$HOME/w" --once);   [[ $out == *$'\n ● src-a  arbeitet\n'"$r46"$'\n f alles'* && $out != *NEU* ]]

# test_foot: the keys, on the right the Claude limits from claude-hud's snapshot (5 h only while it is a number); a
# broken snapshot shows no numbers (Review Focus 3); without a followed session only Enter is offered
fresh; session $$ $s1 src-a "$HOME/w"
out=$(lage --dir "$HOME/w" --once);  [[ $(tail -n 1 <<<"$out") == " f alles   i Idee   ⏎ zur Sitzung" ]]
mkdir -p "$HOME/.cache/claude-hud"; u=$HOME/.cache/claude-hud/usage.json
echo '{"five_hour":{"used_percentage":null,"resets_at":null},"seven_day":{"used_percentage":38.4,"resets_at":"2026-11-20T03:00:00.000Z"}}' >"$u"
last=$(lage --dir "$HOME/w" --once | tail -n 1)
[[ $last == " f alles   i Idee   ⏎ zur Sitzung  "*"Woche 38 %" && ${#last} -eq 46 && $last != *"5 h"* ]]
echo '{"five_hour":{"used_percentage":12},"seven_day":{"used_percentage":38}}' >"$u"
[[ $(COLUMNS=60 lage --dir "$HOME/w" --once | tail -n 1) == *"   5 h 12 % · Woche 38 %" ]]
last=$(lage --dir "$HOME/w" --once | tail -n 1)   # both are too wide for 46 columns: the week alone
[[ $last == " f alles   i Idee   ⏎ zur Sitzung  "*"Woche 38 %" && ${#last} -eq 46 && $last != *"5 h"* ]]
echo '{"five_hour":{"used_percentage":100},"seven_day":{"used_percentage":100}}' >"$u"   # full limits in today's pane
last=$(COLUMNS=56 lage --dir "$HOME/w" --once | tail -n 1);  [[ $last == *"  Woche 100 %" && $last != *"5 h"* ]]
for bad in '' 'kein json' '{"seven_day":null}' '[1]' '{"seven_day":{"used_percentage":"viel"}}' '{"seven_day":{"used_percentage":true}}'; do
  printf '%s' "$bad" >"$u"
  [[ $(lage --dir "$HOME/w" --once | tail -n 1) == " f alles   i Idee   ⏎ zur Sitzung" ]] || { echo "usage: $bad" >&2; false; }
done
out=$(lage --dir "$HOME/empty" --once);  [[ $(tail -n 1 <<<"$out") == " ⏎ zur Sitzung" && $out != *"f alles"* ]]

# test_states_follow (Review Focus 5): the overview follows a transcript that grows while lage runs
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Read","input":{"file_path":"/a/eins.py"}}]')"
python3 -B - "$here" <<'EOF'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import lage

first = lage.states()
assert [(s["sessionId"], state, text) for s, state, _, text in first] == [("aaaaaaaa-1", "arbeitet", "liest eins.py")], first
with (Path.home() / ".claude/projects/p/aaaaaaaa-1.jsonl").open("a") as h:
    h.write('{"type":"assistant","timestamp":"2026-11-15T14:12:10Z","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/zwei.py"}}]}}\n')
assert lage.states()[0][3] == "liest zwei.py", lage.states()
EOF

# test_control_chars: ESC, a C1 character and a second line never reach the terminal
tool Bash '{"description":"x\u001b[2Jy\u009bz\nsecond"}'
[[ $out == *"▶ x?[2Jy?z"* && $out != *$'\e'* && $out != *second* ]]
# every line fits the window
tool Bash '{"description":"'"$(printf 'langer Text %.0s' {1..30})"'"}'
python3 -c 'import sys; sys.exit(max(len(l) for l in sys.stdin.buffer.read().decode().split("\n")) > 46)' <<<"$out"
[[ $out == *"▶ langer Text"*"…"* ]]

# test_ended: the only session in the folder is dead
fresh; session 999999 $s1 src-a "$HOME/w"
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ Sitzung beendet"* ]]
out=$(lage --dir "$HOME/w" --once);  [[ $(sed -n 2p <<<"$out") == "Sitzung beendet" && $out == *$'\n keine Sitzung\n'* ]]   # the overview says it under the header

# test_pick: the newest live session inside the folder wins; dead ones and sibling folders do not
session $$ aaaaaaaa-2 src-b "$HOME/w/a" 1794700100000
session $PPID aaaaaaaa-3 src-c "$HOME/w/b" 1794700200000
session 999998 aaaaaaaa-4 src-d "$HOME/w/c" 1794700300000
session 999997 aaaaaaaa-5 src-e "$HOME/wx" 1794700400000
out=$(lage --dir "$HOME/w" --once);  [[ $out == "LAGE  w/b"* && $out != *"Sitzung beendet"* ]]
out=$(lage --dir "$HOME/w/c" --once);  [[ $out == "LAGE  w/c"* && $out == *"Sitzung beendet"* ]]
out=$(lage --dir "$HOME/wx/" --once);  [[ $out == "LAGE  wx"* ]]

# test_none: nobody in the folder; sessions elsewhere are still listed; the keys offer only Enter (nothing to open or add an idea to)
fresh; out=$(lage --dir "$HOME/empty" --once);  [[ $out == "LAGE"*"14:12"$'\n'"kein Claude in empty"$'\n DU  nichts offen\n'* ]]
session $$ $s1 src-a "$HOME/w"
out=$(lage --dir "$HOME/empty" --once)
[[ $(sed -n 2p <<<"$out") == "kein Claude in empty" && $out == *$'\n ● src-a  arbeitet\n'* && $(tail -n 1 <<<"$out") == " ⏎ zur Sitzung" ]]   # busy, no turn yet

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
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"▶ Protokoll nicht gefunden"* ]]

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

# test_height: main view and full view are never taller than LINES - 1 (the last newline would scroll the pane) nor wider
# than COLUMNS; the header stays on top, the full view keeps its ▶ line; at any height the overview counts every ! line
# it cannot show, and from 8 lines on every session (Review Focus 4)
fresh; session $$ $s1 src-a "$HOME/w"
for m in 00 01 02 03 04 05 06 07 08 09; do entry $s1 "$(assistant 14:11:$m '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"Schritt '"$m"'"}}]')"; done
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
for i in 1 2 3 4 5 6; do live; session $pid "cap0000$i-1" "src-$i" "$HOME/empty"; done
{ for h in Funde Ungeprüft; do echo "## $h"; for m in 00 01 02 03 04; do echo "- 13:$m Eintrag $m"; done; done
  echo '## Für dich'; for m in 00 01 02 03 04; do echo "- 13:$m ! Eintrag $m"; done
  echo '## Deine Ideen'; for m in 00 01 02 03 04; do echo "- [ ] 13:$m Idee $m"; done; } | board
d=$HOME/.local/state/liefern/fertig; mkdir -p "$d"   # GELIEFERT heute, so that both new blocks compete for the rows
for x in 0811 0956 1037 1047; do printf '/x/s.sh\nSatz %s\n' $x >"$d/2026-11-15-$x-s.sh.eintrag"; done
for C in 45 90; do for L in 60 40 27 20 11 8 5; do for v in "" --full; do
  out=$(COLUMNS=$C LINES=$L lage --dir "$HOME/w" --once $v)
  [[ $(wc -l <<<"$out") -le $((L - 1)) && $(widest <<<"$out") -le $C && $(sed -n 1p <<<"$out") == "LAGE  w"* ]] ||
    { echo "COLUMNS=$C LINES=$L $v: $(wc -l <<<"$out") lines" >&2; false; }
  if [[ -n $v ]]; then [[ $out == *$'\n▶ x  seit 20 s'* ]]; else
    steps=$(grep -cE '^ [1-3]  ' <<<"$out" || true); more=$(sed -n 's/^    +\([0-9]*\) weitere$/\1/p' <<<"$out")
    rows=$(grep -cE '^ [●○▲] ' <<<"$out" || true); hidden=$(sed -n 's/^   +\([0-9]*\) weitere Sitzungen$/\1/p' <<<"$out")
    [[ $((steps + ${more:-0})) -eq 5 && ($L -lt 8 || $((rows + ${hidden:-0})) -eq 7) ]] ||
      { echo "COLUMNS=$C LINES=$L: DU $steps+${more:-0}, sessions $rows+${hidden:-0}" >&2; false; }
  fi
done; done; done
out=$(LINES=27 lage --dir "$HOME/w" --once)   # main view: DU with the 3 newest ! lines, the 7 sessions, NEU, GELIEFERT, the keys
[[ $out == *$'\n DU\n 1  Eintrag 04\n 2  Eintrag 03\n 3  Eintrag 02\n    +2 weitere\n─'* && $(grep -c '^─' <<<"$out") -eq 4 ]]
[[ $(grep -cE '^ [●○▲] ' <<<"$out") -eq 7 && $(tail -n 1 <<<"$out") == " f alles   i Idee   ⏎ zur Sitzung" ]]
[[ $out == *$'\n'"$r46"$'\n NEU\n 13:04  src-a\n    Eintrag 04\n'"$r46"$'\n GELIEFERT heute (4)\n 10:47  Satz 1047\n 10:37  Satz 1037\n 09:56  Satz 0956\n'"$r46"$'\n'* ]]
[[ $out != *LOG* && $out != *Schritt* && $out != *"Eintrag 01"* && $out != *"▶"* ]]
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


wait_for("f alles   i Idee".encode())
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


wait_for("f alles   i Idee")
os.write(fd, b"f")
wait_for("FUNDE  1  (1 neu)")
wait_for("i = Idee   f = zurück")
os.write(fd, b"f")
wait_for("f alles   i Idee")  # back in the overview
os.write(fd, b"f")
wait_for("FUNDE  1\x1b[K")  # seen in the full view before: no longer new
with open(board, "a", encoding="utf-8") as f:
    f.write("- 14:12 noch einer\n")  # written later in the same minute: new
wait_for("FUNDE  2  (1 neu)")
# a second, newer session in the folder takes over; its board was never seen, even with the same text
sleeper = subprocess.Popen(["sleep", "60"])
home = Path.home()
(home / ".claude/sessions" / f"{sleeper.pid}.json").write_text(json.dumps(
    {"pid": sleeper.pid, "sessionId": "bbbbbbbb-2", "name": "src-b", "cwd": folder, "startedAt": 1794800000000, "status": "busy"}))
(home / ".claude/projects/p/bbbbbbbb-2.jsonl").write_text(
    '{"type":"user","timestamp":"2026-11-15T14:00:00Z","origin":{"kind":"human"},"message":{"content":"los"}}\n')
(home / ".local/state/lage/bbbbbbbb-2.md").write_text("## Funde\n- 14:12 Fund nach dem Prompt\n")
wait_for("FUNDE  1  (1 neu)")
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
assert any("\x1b" in x and "wartet auf dich" in x for x in lage.frame(session, ended, "in w", True))
EOF

# test_wartet: a line per other waiting session, with its tab title and what it waits for; the followed one never; only the first line of the text
fresh; session $$ $s1 src-a "$HOME/w"
entry $s1 "$(assistant 14:12:00 '"tool_use"' '[{"type":"tool_use","name":"Bash","input":{"description":"x"}}]')"
live; session $pid bbbbbbbb-2 src-c8 "$HOME/empty"
entry bbbbbbbb-2 '{"type":"ai-title","aiTitle":"Bot-Menü","sessionId":"bbbbbbbb-2"}'
entry bbbbbbbb-2 "$(assistant 14:12:00 '"end_turn"' '[{"type":"text","text":"Soll ich es ausrollen, oder erst morgen?\nzweite Zeile"}]')"
out=$(COLUMNS=80 lage --dir "$HOME/w" --once --full)
[[ $out == *$'\n! Bot-Menü wartet: Soll ich es ausrollen, oder erst morgen?\n'* && $out != *"zweite Zeile"* && $out != *src-c8* && $(grep -c ' wartet' <<<"$out") -eq 1 ]]
# a line wider than the window is cut with an ellipsis, never wrapped
out=$(lage --dir "$HOME/w" --once --full);  line=$(grep Bot-Menü <<<"$out")
[[ ${#line} -eq 46 && $line == *"…" && $line == "! Bot-Menü wartet: Soll ich es ausrollen, ode"* ]]
# the followed session waits too: that shows in its ▶ line, never as a waiting line
entry $s1 "$(assistant 14:12:10 '"end_turn"' '[{"type":"text","text":"Fertig, ok?"}]')"
out=$(COLUMNS=60 lage --dir "$HOME/w" --once --full)
[[ $(grep -c '^! ' <<<"$out") -eq 1 && $out == *"▶ wartet auf dich"* && $out != *"src-a wartet"* ]]
# helpers running: it does not wait, no line
sub=$HOME/.claude/projects/p/bbbbbbbb-2/subagents; mkdir -p "$sub"
echo '{}' >"$sub/agent-a1.meta.json"; echo '{}' >"$sub/agent-a1.jsonl"; touch -d 2026-11-15T14:10:00Z "$sub/agent-a1.jsonl"
out=$(COLUMNS=60 lage --dir "$HOME/w" --once --full);  [[ $out != *"Bot-Menü"* ]]

# test_wartet_answered: a question the owner has answered is not shown as waited on again
fresh; session $$ $s1 src-a "$HOME/w"
live; session $pid bbbbbbbb-2 src-b "$HOME/empty"
entry bbbbbbbb-2 "$(assistant 14:11:00 '"end_turn"' '[{"type":"text","text":"Soll ich ausrollen?"}]')"
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"! src-b wartet: Soll ich ausrollen?"* ]]
entry bbbbbbbb-2 '{"type":"user","timestamp":"2026-11-15T14:12:00Z","origin":{"kind":"human"},"message":{"content":"los"}}'
entry bbbbbbbb-2 "$(assistant 14:12:10 '"end_turn"' '[]')"
out=$(lage --dir "$HOME/w" --once --full);  [[ $out == *"! src-b wartet"* && $out != *ausrollen* ]]

# test_wartet_names: a /rename title beats Claude's title, the title beats the name; no title and no name → first 6 characters of the session id; title and name are cut; control characters never reach the terminal
fresh; session $$ $s1 src-a "$HOME/w"
live; echo '{"pid":'"$pid"',"sessionId":"deadbe12-3456","cwd":"/x","startedAt":1794700000000}' >"$HOME/.claude/sessions/$pid.json"
live; session $pid cafe0000-1 "" "$HOME/empty"
entry cafe0000-1 '{"type":"ai-title","aiTitle":"Dies ist ein sehr langer Titel","sessionId":"cafe0000-1"}'
live; session $pid evil0000-1 '\u001b[31mevil name that is long' "$HOME/empty"
entry evil0000-1 '{"type":"ai-title","aiTitle":"a\u001b[0mb\u009bc","sessionId":"evil0000-1"}'
out=$(COLUMNS=80 lage --dir "$HOME/w" --once --full)
[[ $out == *"! deadbe wartet"* && $out == *"! Dies ist ein sehr… wartet"* && $out == *"! a?[0mb?c wartet"* && $out != *cafe00* ]]
[[ $out != *$'\x1b'* && $out != *$'\xc2\x9b'* && $(widest <<<"$out") -le 80 ]]
fresh; session $$ $s1 src-a "$HOME/w"
live; session $pid evil0000-2 '\u001b[31mevil name that is long' "$HOME/empty"
live; session $pid renamed0-1 src-r "$HOME/empty"
entry renamed0-1 '{"type":"ai-title","aiTitle":"Claude-Titel","sessionId":"renamed0-1"}'
entry renamed0-1 '{"type":"custom-title","customTitle":"Mein Titel","sessionId":"renamed0-1"}'
entry renamed0-1 '{"type":"ai-title","aiTitle":"Neuer Claude-Titel","sessionId":"renamed0-1"}'
out=$(COLUMNS=80 lage --dir "$HOME/w" --once --full)
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
out=$(lage --dir "$HOME/w" --once --full)
[[ $(grep -c '^! ' <<<"$out") -eq 2 && $out == *$'! src-1 wartet\n! src-2 wartet\n+3 weitere\n'* && $(widest <<<"$out") -le 46 ]]
# exactly 3: all three, no "+N weitere"
fresh; session $$ $s1 src-a "$HOME/w"
for i in 1 2 3; do live; session $pid "cap0000$i-1" "src-$i" "$HOME/empty"; done
out=$(lage --dir "$HOME/w" --once --full);  [[ $(grep -c '^! ' <<<"$out") -eq 3 && $out != *weitere* ]]

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
out=$(lage --once --full)
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
out=$(lage --once);  [[ $(sed -n 2p <<<"$out") == "kein Claude im Hauptfenster" && $out == *$'\n ● src-a  arbeitet\n'* ]]

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

# test_enter: in the view, Enter focuses the window of the session that waits longest, else of the one working longest;
# a resting (idle) one never, unlike lage bar --focus, which takes idle for waiting (needs a pty)
enter() { # enter <address|"">: lage in a pty, Enter, then the one dispatch it made; "": none, and lage keeps running
  : >"$DISPATCH"
  PATH=$t/fbin:$PATH python3 -B - "$here/lage.py" "$HOME/w" "$DISPATCH" "$1" <<'EOF'
import os
import pty
import select
import signal
import sys
import time

prog, folder, dispatch, want = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("python3", ["python3", prog, "--dir", folder])
seen = b""


def read_until(done, what):
    global seen
    end = time.time() + 8
    while not done() and time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            seen += os.read(fd, 4096)
    assert done(), (what, seen[-300:])


read_until(lambda: "⏎ zur Sitzung".encode() in seen, "first frame")
seen = b""
os.write(fd, b"\r")
if want:
    read_until(lambda: os.path.getsize(dispatch) > 0, "dispatch")
    got = open(dispatch).read()
    assert f'address:{want}"' in got and got.count("dispatch") == 1, got
else:
    read_until(lambda: seen.count(b"\x1b[H") >= 2, "two frames")  # the second frame starts after the Enter was read
    assert os.path.getsize(dispatch) == 0, open(dispatch).read()
os.kill(pid, signal.SIGINT)
assert os.waitpid(pid, 0)[1] == 0
EOF
}
fresh; cls=(); win 0xidle bbbbbbbb-1 idle 14:00:00; win 0xbusy bbbbbbbb-2 busy 14:05:00
focus; [[ $(<"$DISPATCH") == *'address:0xidle'* ]]   # bar --focus takes the idle one
enter 0xbusy
win 0xwait bbbbbbbb-3 waiting 14:10:00; enter 0xwait
fresh; cls=(); win 0xidle bbbbbbbb-1 idle 14:00:00; win 0xrest bbbbbbbb-2 idle 14:05:00; enter ""

# test_never_dies: an odd session file (a NUL in its id) never ends the view: the round shows the error, Enter does
# nothing (it runs for hours in the Cockpit; --once still fails loudly)
fresh; session $$ $s1 src-a "$HOME/w"; live
python3 -c 'import json, sys; print(json.dumps({"pid": int(sys.argv[1]), "sessionId": "b\0d", "cwd": sys.argv[2], "status": "busy"}))' \
  "$pid" "$HOME/w" >"$HOME/.claude/sessions/$pid.json"
rc=0; lage --dir "$HOME/w" --once >/dev/null 2>&1 || rc=$?;  [[ $rc -ne 0 ]]
python3 -B - "$here/lage.py" "$HOME/w" <<'EOF'
import os
import pty
import select
import signal
import sys
import time

prog, folder = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("python3", ["python3", prog, "--dir", folder])
seen = b""


def read_until(done, what):
    global seen
    end = time.time() + 8
    while not done() and time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            try:
                seen += os.read(fd, 4096)
            except OSError:  # lage ended: its side of the pty is gone
                break
    assert done(), (what, seen[-300:])


read_until(lambda: b"lage: " in seen, "error line")
seen = b""
os.write(fd, b"\r")
read_until(lambda: seen.count(b"\x1b[H") >= 2, "two rounds after Enter")
os.kill(pid, signal.SIGINT)
assert os.waitpid(pid, 0)[1] == 0
EOF

# test_schritt_new: a new step, every key, status laeuft, the session's own file
fresh; session $$ $s1 src-a "$HOME/w"
lage schritt "Port 80 prüfen" --warum "w1" --gesendet "g1" --ziel "Router" --weg "Web"
sf=$HOME/.local/state/lage/$s1.schritte.jsonl
[[ $(wc -l <"$sf") -eq 1 ]]
jq -e '.zeit == "2026-11-15T14:12:20+00:00" and .status == "laeuft" and .was == "Port 80 prüfen" and .warum == "w1"
  and .gesendet == "g1" and .ziel == "Router" and .weg == "Web" and .antwort == "" and .bedeutung == ""
  and (keys | length) == 9' "$sf"

# test_schritt_finish: without WAS the newest non-offen step is copied, given fields win, status kept unless given
lage schritt "Y später" --weg "Seriell" --status offen
lage schritt --antwort "teil"
lage schritt --antwort "a1" --bedeutung "b1" --status fund
[[ $(wc -l <"$sf") -eq 4 ]]
jq -se '.[2].status == "laeuft" and .[2].was == "Port 80 prüfen" and .[2].antwort == "teil"
  and .[3].status == "fund" and .[3].warum == "w1" and .[3].gesendet == "g1" and .[3].weg == "Web" and .[3].bedeutung == "b1"' "$sf"

# test_schritt_errors: nothing to change, no session, a wrong status; nothing is written then
fresh; session $$ $s1 src-a "$HOME/w"
rc=0; lage schritt --antwort x 2>"$t/err" || rc=$?; [[ $rc -eq 1 && $(<"$t/err") == *"noch kein Schritt"* ]]
fresh; session 999999 $s1 src-a "$HOME/w"
rc=0; lage schritt "x" 2>"$t/err" || rc=$?; [[ $rc -eq 1 && $(<"$t/err") == *"keine Claude-Sitzung"* && ! -e $HOME/.local/state ]]
fresh; session $$ $s1 src-a "$HOME/w"; rc=0; lage schritt "x" --status info 2>/dev/null || rc=$?; [[ $rc -eq 2 ]]
lage schritt "y"; sf=$HOME/.local/state/lage/$s1.schritte.jsonl; before=$(<"$sf")
rc=0; lage schritt 2>"$t/err" || rc=$?; [[ $rc -eq 1 && $(<"$t/err") == *"nichts zu ändern"* && $(<"$sf") == "$before" ]]
rc=0; lage schritt "  " 2>"$t/err" || rc=$?; [[ $rc -eq 1 && $(<"$t/err") == *"nichts zu ändern"* && $(<"$sf") == "$before" ]]

# test_schritt_clean: first line only, control characters as ?, cut to 200 with …; an empty WAS counts as missing
fresh; session $$ $s1 src-a "$HOME/w"
sf=$HOME/.local/state/lage/$s1.schritte.jsonl
lage schritt "$(printf 'a\033[2Jb\nzweite')" --warum "$(printf 'x%.0s' {1..300})"
jq -e '.was == "a?[2Jb" and (.warum | length) == 200 and (.warum | endswith("…"))' "$sf"
lage schritt "  " --antwort "leer"
jq -se 'length == 2 and .[1].was == "a?[2Jb" and .[1].antwort == "leer"' "$sf"

# test_schritt_zeit: an update of a running step keeps its start time, any other change takes the new time
fresh; session $$ $s1 src-a "$HOME/w"
sf=$HOME/.local/state/lage/$s1.schritte.jsonl
lage schritt "läuft lange"
LAGE_NOW=2026-11-15T14:13:00Z lage schritt --gesendet x
LAGE_NOW=2026-11-15T14:14:00Z lage schritt --antwort a --status fund
LAGE_NOW=2026-11-15T14:15:00Z lage schritt --antwort b
jq -se 'length == 4 and .[0].zeit == "2026-11-15T14:12:20+00:00" and .[1].zeit == "2026-11-15T14:12:20+00:00" and .[1].gesendet == "x"
  and .[2].zeit == "2026-11-15T14:14:00+00:00" and .[2].status == "fund"
  and .[3].zeit == "2026-11-15T14:15:00+00:00" and .[3].status == "fund"' "$sf"

# test_schritt_lab: a session started inside a lab folder writes next to the lab board
fresh; mkdir -p "$HOME/src/sec/live/x/sub"; session $$ $s1 src-a "$HOME/src/sec/live/x/sub"
lage schritt "im Lab"; [[ -s $HOME/src/sec/live/x/.claude/lage.schritte.jsonl ]]

# test_schritt_parallel (Review Focus 1): two writers at once never interleave a line (lines longer than 150 bytes)
fresh; session $$ $s1 src-a "$HOME/w"
wp=(); for w in a b; do (for i in $(seq 25); do lage schritt "$w$i" --warum "$(printf 'y%.0s' {1..150})"; done) & wp+=($!); done
wait "${wp[@]}"  # not a bare wait: it would also wait for the sleeping `live` processes
[[ $(jq -c . "$HOME/.local/state/lage/$s1.schritte.jsonl" | wc -l) -eq 50 ]]

# test_read_steps (Review Focus 2): only the last 500 good lines, bad lines skipped, a missing file is empty
fresh
python3 -B - "$here" <<'EOF'
import json
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import lage

f = Path.home() / "steps.jsonl"
rec = {k: "" for k in lage.STEP_KEYS}
lines = []
for i in range(510):
    lines.append(json.dumps({**rec, "zeit": "2026-11-15T14:12:20+00:00", "was": f"s{i}", "status": "laeuft"}))
    if i == 100:
        lines += ["{broken", json.dumps({**rec, "was": "info", "status": "info"}), "[1, 2]"]
f.write_text("\n".join(lines) + "\n")
got = lage.read_steps(f)
assert len(got) == 500 and got[0]["was"] == "s10" and got[-1]["was"] == "s509", (len(got), got[0]["was"])
assert all(r["ts"] is not None and set(lage.STEP_KEYS) <= set(r) for r in got)
assert lage.read_steps(Path.home() / "nope.jsonl") == []
g = Path.home() / "sep.jsonl"  # U+2028 and U+2029 inside a record must not split its line
g.write_text("".join(json.dumps({**rec, "was": w, "status": "fund"}, ensure_ascii=False) + "\n" for w in ("a\u2028b\u2029c", "danach")))
assert [r["was"] for r in lage.read_steps(g)] == ["a\u2028b\u2029c", "danach"], lage.read_steps(g)
EOF

# test_work_three_steps (Done 1): three steps, the newest on top with all five fields, the older ones with ← and =
fresh; session $$ $s1 src-a "$HOME/w"
lage schritt "Port 80 prüfen" --warum "w1" --gesendet "g1"; lage schritt --antwort "a1" --bedeutung "b1" --status zu
lage schritt "Login testen" --warum "w2"
lage schritt "NTP fragen" --ziel "Router" --warum "w3" --gesendet "g3" --antwort "a3" --bedeutung "b3" --status fund
out=$(lage --dir "$HOME/w" --once --arbeit)
[[ $(head -n 1 <<<"$out") == "LAGE  src-a · ARBEIT"*"14:12" && $out == *$'\nZIEL  Router\n'* ]]
[[ $out == *"✔ NTP fragen"* && $out == *"warum   w3"* && $out == *"sendet  g3"* && $out == *"←       a3"* && $out == *"=       b3"* ]]
[[ $out == *"· 14:12  Login testen"* && $out == *"✖ 14:12  Port 80 prüfen"*$'\n  ← a1\n  = b1'* ]]
[[ $out != *"Port 80 prüfen"*"Port 80 prüfen"* ]]          # the finish hides its start line
widest <<<"$out" | { read -r w; ((w <= 46)); }
out30=$(COLUMNS=30 lage --dir "$HOME/w" --once --arbeit); widest <<<"$out30" | { read -r w; ((w <= 30)); }
# a running top step says that no answer is there yet, and how long it runs
lage schritt "Scan" --warum "w4"; out=$(LAGE_NOW=2026-11-15T14:13:00Z lage --dir "$HOME/w" --once --arbeit)
[[ $out == *"▶ Scan"*"seit 40 s"* && $out == *"←       noch keine Antwort"* ]]

# test_work_merge (Done 2): 20 equal warnings between other steps are one row
fresh; session $$ $s1 src-a "$HOME/w"
for i in $(seq 20); do lage schritt "IPv4 fällt aus" --status warn --bedeutung "Aussetzer"; ((i % 7)) || lage schritt "Schritt $i" --status zu; done
out=$(LINES=40 lage --dir "$HOME/w" --once --arbeit)
[[ $(grep -c "IPv4 fällt aus" <<<"$out") -eq 1 && $out == *"IPv4 fällt aus  ×20"* ]]

# test_work_ways (Review Focus 5): a warn never changes a way, the first open way not running is next
fresh; session $$ $s1 src-a "$HOME/w"
lage schritt "X1" --weg "Web" --status fund; lage schritt "Y" --weg "Seriell" --status offen
lage schritt "Z" --weg "Chip" --status offen; lage schritt "Aussetzer" --weg "Web" --status warn
lage schritt "Chip lesen" --weg "Chip"
out=$(lage --dir "$HOME/w" --once --arbeit)
[[ $out == *$'\nWEGE  ✔ 1  ? 2\n▶ Chip\n? Seriell'*"→ als Nächstes"* && $out == *"✔ Web"* && $out != *"⚠ Web"* ]]

# test_work_ways_cap: at most 6 ways, the rest counted
fresh; session $$ $s1 src-a "$HOME/w"
for i in 1 2 3 4 5 6 7 8; do lage schritt "W$i" --weg "Weg $i" --status offen; done; lage schritt "Los"
out=$(LINES=40 lage --dir "$HOME/w" --once --arbeit)
[[ $out == *$'WEGE  ? 8\n? Weg 1'*"→ als Nächstes"*$'\n? Weg 6\n+2 weitere'* && $out != *"Weg 7"* ]]

# test_work_empty and test_work_source: no steps; the followed session has none, another live one has
fresh; session $$ $s1 src-a "$HOME/w"; out=$(lage --dir "$HOME/w" --once --arbeit); [[ $out == *"Noch keine Schritte"* && $out == *"lage schritt"* ]]
live; session $pid bbbbbbbb-2 src-b "$HOME/empty"; mkdir -p "$HOME/.local/state/lage"
echo '{"zeit":"2026-11-15T14:00:00+00:00","ziel":"","weg":"","was":"fremd","warum":"","gesendet":"","antwort":"","bedeutung":"","status":"laeuft"}' \
  >"$HOME/.local/state/lage/bbbbbbbb-2.schritte.jsonl"
out=$(lage --dir "$HOME/w" --once --arbeit); [[ $(head -n 1 <<<"$out") == "LAGE  src-b · ARBEIT"* && $out == *"▶ fremd"* ]]

# test_work_days: a time on another day shows DD.MM., a record without a time shows none
fresh; session $$ $s1 src-a "$HOME/w"; mkdir -p "$HOME/.local/state/lage"
rec() { jq -nc --arg z "$1" --arg w "$2" --arg s "$3" '{zeit:$z,ziel:"",weg:"",was:$w,warum:"",gesendet:"",antwort:"",bedeutung:"",status:$s}'; }
{ rec 2026-11-13T09:00:00+00:00 Älter zu; rec "" Ohne zu; rec 2026-11-14T09:00:00+00:00 Gestern fund; } >"$HOME/.local/state/lage/$s1.schritte.jsonl"
out=$(lage --dir "$HOME/w" --once --arbeit); blank='✖ {8}Ohne'
[[ $out == *"✔ Gestern"*"14.11."$'\n'* && $out == *"✖ 13.11.  Älter"* && $out =~ $blank ]]

# test_work_small: a small pane keeps head, top and foot and drops older steps first (+N ältere)
fresh; session $$ $s1 src-a "$HOME/w"
for i in 1 2 3 4 5 6; do lage schritt "Schritt $i" --weg "Weg $((i % 3))" --antwort "a$i" --bedeutung "b$i" --status zu; done
out=$(LINES=14 lage --dir "$HOME/w" --once --arbeit)
[[ $(wc -l <<<"$out") -le 13 && $(head -n 1 <<<"$out") == "LAGE  src-a · ARBEIT"* && $(tail -n 1 <<<"$out") == " s Stopp  ? Frage  i Idee  a zurück" ]]
[[ $out == *"✖ Schritt 6"* && $out == *"+5 ältere"* && $out == *"WEGE"* ]]
out=$(LINES=3 lage --dir "$HOME/w" --once --arbeit); [[ $(wc -l <<<"$out") -eq 2 ]]   # only the head and the foot fit

echo ok
