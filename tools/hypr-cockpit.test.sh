#!/usr/bin/env bash
# Test for hypr-cockpit: fake hyprctl, a kitty stub, a fake HOME and runtime dir, a fake claude. No real Hyprland.
# Run: tools/hypr-cockpit.test.sh <built hypr-cockpit script>
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
script=$(realpath "${1:?usage: hypr-cockpit.test.sh <built hypr-cockpit script>}")
t=$(mktemp -d); sl=(); trap 'rm -rf "$t"; ((${#sl[@]})) && kill -- "${sl[@]}" 2>/dev/null || true' EXIT
export HOME=$t/home XDG_RUNTIME_DIR=$t/run KITTY_LOG=$t/kitty.log HYPR_LOG=$t/hypr.log HYPR_COCKPIT_KITTY=$t/bin/kitty
mkdir -p "$HOME/.claude/sessions" "$XDG_RUNTIME_DIR" "$t/bin"
printf '#!/bin/sh\nsleep 60\n' >"$t/bin/claude" # its /proc comm is "claude"
cat >"$t/bin/hyprctl" <<'FAKE'
#!/bin/sh
case "$*" in
  "activeworkspace -j") echo '{"id":1,"windows":2,"hasfullscreen":false,"tiledLayout":"dwindle"}' ;;
  "clients -j") printf '%s\n' "$CLIENTS" ;;
  *) echo "$*" >>"$HYPR_LOG" ;;
esac
FAKE
cat >"$t/bin/kitty" <<'FAKE'
#!/bin/sh
echo "$*" >"$KITTY_LOG.tmp" && mv "$KITTY_LOG.tmp" "$KITTY_LOG"
FAKE
chmod +x "$t"/bin/*
export PATH=$t/bin:$PATH

die() { echo "FAIL: $*" >&2; exit 1; } # the ERR trap does not reach into functions
waitcomm() { local i; for i in {1..100}; do [[ $(cat /proc/$1/comm 2>/dev/null) == "$2" ]] && return 0; sleep 0.05; done; die "process $1 never became $2"; } # waitcomm <pid> <comm>
window() { # window <program>: a shell standing in for kitty, the program its child. Sets $wrapper and $child.
  local i; rm -f "$t/child"
  setsid sh -c '"$@" & echo $! >"$0"; wait; sleep 60' "$t/child" "$@" &
  wrapper=$!; sl+=("-$wrapper")                                         # the whole process group dies in the trap
  for i in {1..100}; do [[ -s $t/child ]] && break; sleep 0.05; done
  child=$(<"$t/child"); waitcomm "$child" "${1##*/}"
}
claude_window() { # a window running claude with a sessions file. Sets $wrapper.
  window "$t/bin/claude"
  echo '{"pid":'"$child"',"sessionId":"aaaaaaaa-1","name":"src-a","cwd":"/x","startedAt":1794700000000}' >"$HOME/.claude/sessions/$child.json"
}
plain_window() { sleep 600 & sl+=($!); wrapper=$!; } # a window with no claude. Sets $wrapper.
cl() { # cl <pid> <class> <focusHistoryID>: one tiled client of workspace 1 as hyprctl prints it
  jq -nc --argjson p "$1" --arg c "$2" --argjson i "$3" \
    '{pid: $p, address: "0x\($p)", class: $c, workspace: {id: 1}, hidden: false, floating: false, grouped: [], focusHistoryID: $i}'; }
run() { # the script once, then wait up to 2 s for the detached kitty stub and drop the state file
  local i; rm -f "$KITTY_LOG" "$HYPR_LOG"; CLIENTS=$(printf '%s\n' "$@" | jq -sc .); export CLIENTS
  "$script"
  for i in {1..40}; do [[ -e $KITTY_LOG ]] && break; sleep 0.05; done
  rm -f "$XDG_RUNTIME_DIR/hypr-cockpit/1"
}

# test_plain_one_window: no Claude, one tiled window: the old journalctl pane
plain_window; w1=$wrapper
run "$(cl $w1 foot 0)"
[[ $(<"$KITTY_LOG") == "--class cockpit-log journalctl -f" ]]

# test_plain_two_windows: no Claude, two tiled windows: no pane
plain_window; w2=$wrapper
run "$(cl $w1 foot 0)" "$(cl $w2 foot 1)"
[[ ! -s $KITTY_LOG ]]

# test_claude_two_windows: the work window runs Claude: lage opens although a second window is there
claude_window; c1=$wrapper
run "$(cl $c1 kitty 0)" "$(cl $w2 foot 1)"
[[ $(<"$KITTY_LOG") == "--class cockpit-log /nix/store/"*"/bin/lage" ]]
grep -q 'layout = "master"' "$HYPR_LOG"                          # the layout part is untouched

# test_claude_pane_exists: same, but the pane is already there
run "$(cl $c1 kitty 0)" "$(cl $w2 foot 1)" "$(cl $w1 cockpit-log 2)"
[[ ! -s $KITTY_LOG ]]

echo ok
