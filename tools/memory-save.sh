#!/usr/bin/env bash
# Claude Code SessionEnd and SessionStart hook, same file on every device: drops
# the finished session's text into the shared memory's inbox (MCP tool bm_write
# on svc:memory); at start it catches up on unsaved ones. bandit-lab turns them
# into session notes (services/memory). Test: tools/memory-save.test.sh
# Needs bash, curl, jq. Reads the hook JSON on stdin.
set -euo pipefail
HOST=memory.tail7facc9.ts.net
# Dial the service address directly: Termux cannot resolve tailnet names.
ADDR=${MEMORY_ADDR:-100.103.202.198}

if [ "${1:-}" != --fg ]; then
  # Detach so a slow network never holds up the exit.
  input=$(cat)
  mkdir -p "$HOME/.local/state"
  printf '%s' "$input" | setsid -f "$0" --fg >/dev/null 2>>"$HOME/.local/state/memory-save.log"
  exit 0
fi

input=$(cat)
saved="$HOME/.local/state/memory-saved" # one file per session: prompt count last saved
mkdir -p "$saved"
if [ "$(jq -r '.hook_event_name // empty' <<<"$input")" = SessionStart ]; then
  # Sessions mostly end by shutdown, when the network is already gone, so each
  # start saves every transcript idle for an hour that changed since its last save.
  # shortcut: only the last 3 days are swept; a session idle longer than that before it ends is never saved.
  find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -mtime -3 -mmin +60 |
    while read -r f; do
      s=$(basename "$f" .jsonl)
      [ "$f" -nt "$saved/$s" ] || continue
      jq -n --arg t "$f" --arg s "$s" '{transcript_path: $t, session_id: $s}' | "$0" --fg || true
    done
  exit 0
fi
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
sid=$(jq -r '.session_id // empty' <<<"$input")
[ -r "$transcript" ] && [[ $sid =~ ^[0-9a-f-]{8,}$ ]] || exit 0
# Start directory and day, not the current ones, so a later save keeps the note name.
cwd=$(jq -rn 'first(inputs | .cwd // empty)' "$transcript")
day=$(jq -rn 'first(inputs | .timestamp // empty)' "$transcript" | cut -c1-10)

# What the user typed and what the assistant answered, without tool output.
text=$(jq -r '
  if .type == "user" and (.message.content | type) == "string" then "USER: " + .message.content
  elif .type == "assistant" then (.message.content[]? | select(.type == "text") | "ASSISTANT: " + .text)
  else empty end' "$transcript" | grep -v '^USER: <' || true)
n=$(grep -c '^USER: ' <<<"$text" || true)
# Saved already with these prompts: Claude still appends a few lines after SessionEnd.
[ "$(cat "$saved/$sid" 2>/dev/null)" != "$n" ] || { touch "$saved/$sid"; exit 0; }
# Nothing worth a note in a session with fewer than three prompts.
[ "$n" -ge 3 ] || { echo "$n" >"$saved/$sid"; exit 0; }
text=$(tail -c 24000 <<<"$text")

project=$(basename "${cwd:-unknown}" | tr -c 'A-Za-z0-9._\n-' '-')
device=$(printf "%s\n" "${MEMORY_DEVICE:-$(hostname)}" | tr -c 'A-Za-z0-9._\n-' '-')
name="${day:-$(date +%F)}-$device-$project-${sid:0:8}"

mcp() { # mcp <json> [session]: one JSON-RPC message; prints headers then body
  curl -fsS -m 60 -D - --resolve "$HOST:443:$ADDR" "https://$HOST/mcp" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    ${2:+-H "mcp-session-id: $2"} -d "$1"
}
session=$(mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"memory-save","version":"1"}}}' \
  | tr -d '\r' | awk 'tolower($1) == "mcp-session-id:" {print $2}')
[ -n "$session" ] || { echo "$(date -Is) $name: no session from memory server" >&2; exit 1; }
mcp '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$session" >/dev/null
reply=$(jq -n --arg n "$name" --arg t "$text" --arg d "$device" --arg p "$project" \
  '{jsonrpc: "2.0", id: 2, method: "tools/call", params: {name: "bm_write", arguments:
    {project: "main", directory: "inbox", title: $n, content: $t, tags: ["inbox", $d, $p], overwrite: true}}}' \
  | mcp @- "$session")
grep -q '"isError":false' <<<"$reply" || { echo "$(date -Is) $name: $(tail -c 300 <<<"$reply")" >&2; exit 1; }
echo "$n" >"$saved/$sid"
echo "$(date -Is) saved inbox/$name" >&2
