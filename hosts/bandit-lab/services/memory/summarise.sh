# Turns raw session transcripts that devices drop into the store's inbox/ (via
# the MCP tool bm_write) into short session notes, using the lab's Ollama.
# A file that fails stays in the inbox and is retried on the next run.
store=${MEMORY_STORE:-/srv/containers/memory/data/basic-memory}
# mistral was fast but reported plans as done; qwen3-coder:30b got the facts right (2026-11-11).
model=${MEMORY_MODEL:-qwen3-coder:30b}
prompt="Summarise this coding-assistant session for a shared long-term memory that other agents read later.
Write English Markdown with exactly these sections:
## Goal
## Done
## Decisions
## Open
Short bullet points, concrete names (files, commands, hosts). Only facts stated in the session.
NEVER include passwords, tokens, keys or other secrets. No introduction, no closing remark."

shopt -s nullglob
mkdir -p "$store/sessions"
for file in "$store"/inbox/*.md; do
  # Named <day>-<device>-<project>-<session8> by the device's hook.
  name=$(basename "$file" .md)
  [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || continue
  # Body without the front matter Basic Memory adds.
  text=$(awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm' "$file" | tail -c 24000)
  [ -n "$text" ] || { rm -f "$file"; continue; }
  # keep_alive 0 hands the GPU back to ComfyUI and the bots right away.
  summary=$(jq -n --arg m "$model" --arg p "$prompt" --arg t "$text" \
    '{model: $m, stream: false, keep_alive: 0, options: {temperature: 0.2, num_ctx: 16384},
      messages: [{role: "system", content: $p}, {role: "user", content: $t}]}' \
    | curl -fsS -m 900 http://127.0.0.1:11434/api/chat -d @- | jq -r '.message.content // empty') || summary=
  if [ -z "$summary" ]; then
    echo "no summary for $name, will retry" >&2
    continue
  fi
  tags=$(awk '/^tags:/ {t=1; next} t && /^- / {print; next} t {exit}' "$file" | grep -v '^- inbox$' || true)
  {
    printf -- '---\ntitle: %s\ntype: session\ntags:\n- session\n' "$name"
    [ -z "$tags" ] || printf '%s\n' "$tags"
    printf -- '---\n\n%s\n' "$summary"
  } > "$store/sessions/$name.md"
  rm -f "$file"
  echo "summarised $name"
done
