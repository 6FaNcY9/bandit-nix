#!/usr/bin/env bash
# Claude Code SessionEnd hook, same file on every device: drops the finished
# session's text into the shared memory's inbox (MCP tool bm_write on
# svc:memory). bandit-lab turns it into a session note (services/memory).
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
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
sid=$(jq -r '.session_id // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -r "$transcript" ] && [[ $sid =~ ^[0-9a-f-]{8,}$ ]] || exit 0

# What the user typed and what the assistant answered, without tool output.
text=$(jq -r '
  if .type == "user" and (.message.content | type) == "string" then "USER: " + .message.content
  elif .type == "assistant" then (.message.content[]? | select(.type == "text") | "ASSISTANT: " + .text)
  else empty end' "$transcript" | grep -v '^USER: <' || true)
# Nothing worth a note in a session with fewer than three prompts.
[ "$(grep -c '^USER: ' <<<"$text")" -ge 3 ] || exit 0
text=$(tail -c 24000 <<<"$text")

project=$(basename "${cwd:-unknown}" | tr -c 'A-Za-z0-9._\n-' '-')
device=$(hostname | tr -c 'A-Za-z0-9._\n-' '-')
name="$(date +%F)-$device-$project-${sid:0:8}"

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
echo "inbox/$name"
