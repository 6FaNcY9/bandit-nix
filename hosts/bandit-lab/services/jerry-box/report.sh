NTFY_URL=${NTFY_URL:-http://127.0.0.1:2586}
NTFY_TOPIC=${NTFY_TOPIC:-mcbots}
STATE_FILE=${STATE_FILE:-/var/lib/jerry-report/cursor}

if [ -n "${JERRY_JOURNAL_FILE:-}" ]; then
  records=$(cat "$JERRY_JOURNAL_FILE")
elif [ -s "$STATE_FILE" ]; then
  records=$(journalctl _TRANSPORT=audit -o json --after-cursor "$(cat "$STATE_FILE")")
else
  records=$(journalctl _TRANSPORT=audit -o json --since -1h)
fi

records=$(printf '%s\n' "$records" | jq -c 'select(._AUDIT_TYPE_NAME == "SYSCALL" and (.MESSAGE | contains("key=\"jerry\"")))')
[ -n "$records" ] || exit 0

body=$(printf '%s\n' "$records" |
  jq -r '.MESSAGE | capture("exit=(?<e>-?[0-9]+) .*comm=\"(?<c>[^\"]*)\"") | "\(.c) \(.e)"' |
  awk '{n[$1]++; if ($2 != 0) f[$1]++} END {for (c in n) printf "%d %s %d\n", n[c], c, f[c]}' |
  sort -k1,1nr -k2,2 | awk '{printf "%dx %s (%d failed)\n", $1, $2, $3}')
total=$(printf '%s\n' "$records" | wc -l)
cursor=$(printf '%s\n' "$records" | tail -n1 | jq -r .__CURSOR)

# CURL overrides the binary so tests can inject a stub.
if printf '%s\n' "$body" | "${CURL:-curl}" -fsS -H "Authorization: Bearer ${NTFY_TOKEN:-}" \
  -H "Title: Jerry box: $total processes" --data-binary @- "$NTFY_URL/$NTFY_TOPIC"; then
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '%s\n' "$cursor" >"$STATE_FILE"
else
  echo "jerry-report: ntfy POST failed, will retry next run" >&2
fi
