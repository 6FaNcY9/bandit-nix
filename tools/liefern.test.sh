#!/usr/bin/env bash
# Test for tools/liefern with fake scripts in a temp dir. Run: tools/liefern.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export HOME=$t/home LIEFERN_DIR=$t/q
mkdir -p "$HOME"
l() { bash "$here/liefern" "$@"; }
mk() { printf '#!/usr/bin/env bash\necho "%s" >>"%s/log"\nexit %s\n' "$1" "$t" "${2:-0}" >"$HOME/$1.sh"; }

# empty queue: one sentence, exit 0, for both forms
[[ $(l -n) == "Nichts zu liefern." && $(l </dev/null) == "Nichts zu liefern." ]]

# add keeps the order of adding; a missing script, an empty sentence and a duplicate are refused
mk eins
mk zwei 1
mk drei
l add "$HOME/eins.sh" "Erstes Ding" >/dev/null
l add "$HOME/zwei.sh" "Zweites Ding" >/dev/null
out=$(l add "$HOME/drei.sh" "Drittes Ding")
[[ $out == "Eingestellt als Nr. 3: Drittes Ding" ]]
l add "$HOME/fehlt.sh" "x" 2>/dev/null && exit 1
l add "$HOME/eins.sh" "" 2>/dev/null && exit 1
l add "$HOME/eins.sh" "nochmal" 2>/dev/null && exit 1
[[ $(l -n) == $'1. Erstes Ding\n2. Zweites Ding\n3. Drittes Ding' ]]

# no: nothing runs
out=$(echo n | l)
[[ $out == *"Nichts geliefert."* && ! -e $t/log ]]

# yes: runs in order, stops at the first error, the failed one and the rest stay queued
rc=0
out=$(echo j | l 2>&1) || rc=$?
[[ $rc == 1 && $(<"$t/log") == $'eins\nzwei' ]]
[[ $out == *"STOPP bei Nr. 2: Zweites Ding"* && $out == *"$HOME/zwei.sh"* && $out == *"Exit-Code 1"* && $out == *"2 bleiben in der Schlange"* ]]
[[ $(l -n) == $'1. Zweites Ding\n2. Drittes Ding' ]]
# the done one moved with its date, its loose script in ~ too
compgen -G "$LIEFERN_DIR/fertig/????-??-??-????-eins.sh.eintrag" >/dev/null
compgen -G "$LIEFERN_DIR/fertig/????-??-??-????-eins.sh" >/dev/null
[[ ! -e $HOME/eins.sh && -e $HOME/zwei.sh ]]

# fixed: the rest runs, the queue is empty
mk zwei
echo j | l >/dev/null
[[ $(<"$t/log") == $'eins\nzwei\nzwei\ndrei' && $(l -n) == "Nichts zu liefern." ]]

# a script that is gone by the time it runs stops the run
mk vier
l add "$HOME/vier.sh" "Viertes Ding" >/dev/null
rm "$HOME/vier.sh"
out=$(echo j | l 2>&1) && exit 1
[[ $out == *"STOPP bei Nr. 1: Viertes Ding"* && $out == *"gibt es nicht mehr"* ]]

# a script outside ~ is left where it is (it may be part of a repo)
mkdir -p "$t/repo"
printf '#!/usr/bin/env bash\ntrue\n' >"$t/repo/tool.sh"
rm "$LIEFERN_DIR"/warten/*
l add "$t/repo/tool.sh" "Repo-Ding" >/dev/null
echo j | l >/dev/null
[[ -e $t/repo/tool.sh && $(l -n) == "Nichts zu liefern." ]]
echo ok
