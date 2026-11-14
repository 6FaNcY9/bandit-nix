#!/usr/bin/env bash
# Test for tools/memory-save.sh with a fake HOME and a fake curl that answers like
# the memory server. Run: tools/memory-save.test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/home/.claude/projects/p"
cat >"$t/bin/curl" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = -d ] && body=$2; shift; done
[ "$body" = @- ] && body=$(cat)
case $body in
  *'"initialize"'*) printf 'HTTP/1.1 200 OK\r\nmcp-session-id: s1\r\n\r\n{}' ;;
  *bm_write*) jq -r .params.arguments.title <<<"$body" >>"$CALLS"; echo '{"result":{"isError":false}}' ;;
esac
EOF
chmod +x "$t/bin/curl"
export HOME=$t/home PATH=$t/bin:$PATH CALLS=$t/calls MEMORY_DEVICE=dev
: >"$CALLS"
p=$HOME/.claude/projects/p
prompts() { # prompts <file> <count>: a transcript with that many user prompts
  for i in $(seq "$2"); do
    echo '{"type":"user","cwd":"/x/proj","timestamp":"2026-11-10T09:00:00Z","message":{"content":"q'"$i"'"}}'
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"a'"$i"'"}]}}'
  done >"$1"
}
sweep() { echo '{"hook_event_name":"SessionStart"}' | "$here/memory-save.sh" --fg; }
prompts "$p/aaaaaaaa-1.jsonl" 3; touch -d '2 hours ago' "$p/aaaaaaaa-1.jsonl"   # idle, unsaved
prompts "$p/bbbbbbbb-1.jsonl" 2; touch -d '2 hours ago' "$p/bbbbbbbb-1.jsonl"   # too short
prompts "$p/cccccccc-1.jsonl" 3                                                # still active

sweep
[[ $(cat "$CALLS") == 2026-11-10-dev-proj-aaaaaaaa ]]                   # only the idle one, named by its start
[[ $(cat "$HOME/.local/state/memory-saved/aaaaaaaa-1") == 3 ]]
[[ $(cat "$HOME/.local/state/memory-saved/bbbbbbbb-1") == 2 ]]

sweep; [[ $(wc -l <"$CALLS") -eq 1 ]]                                   # nothing new: nothing sent

# Lines written after the save (Claude does that at exit) but no new prompt: not sent again.
touch -d '3 hours ago' "$HOME/.local/state/memory-saved/aaaaaaaa-1"
sweep; [[ $(wc -l <"$CALLS") -eq 1 ]]

# The session went on: saved again under the same name.
prompts "$p/aaaaaaaa-1.jsonl" 4; touch -d '2 hours ago' "$p/aaaaaaaa-1.jsonl"
touch -d '3 hours ago' "$HOME/.local/state/memory-saved/aaaaaaaa-1"
sweep; [[ $(tail -n 1 "$CALLS") == 2026-11-10-dev-proj-aaaaaaaa && $(wc -l <"$CALLS") -eq 2 ]]

# SessionEnd still saves right away, active or not.
echo "{\"transcript_path\":\"$p/cccccccc-1.jsonl\",\"session_id\":\"cccccccc-1\"}" | "$here/memory-save.sh" --fg
[[ $(tail -n 1 "$CALLS") == 2026-11-10-dev-proj-cccccccc ]]
echo ok
