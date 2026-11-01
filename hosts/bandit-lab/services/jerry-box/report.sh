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

all=$records
records=$(printf '%s\n' "$records" | jq -c 'select(._AUDIT_TYPE_NAME == "SYSCALL" and (.MESSAGE | contains("key=\"jerry\"")))')
# The cursor follows the last record of any kind, so quiet hours still advance it.
last=$(printf '%s\n' "$all" | tail -n1)
[ -n "$last" ] || exit 0
cursor=$(printf '%s\n' "$last" | jq -r .__CURSOR)
quiet() { mkdir -p "$(dirname "$STATE_FILE")"; printf '%s\n' "$cursor" >"$STATE_FILE"; exit 0; }
[ -n "$records" ] || quiet

# One "comm<TAB>exit" row per record; the kernel hex-encodes comm when it has spaces or special chars.
rows=$(printf '%s\n' "$records" |
  jq -r '.MESSAGE | capture("exit=(?<e>-?[0-9]+) .*comm=(?:\"(?<c>[^\"]*)\"|(?<h>[0-9A-Fa-f]+))")? | [.c // "", .h // "", .e] | join("\u001f")' |
  while IFS=$'\037' read -r c h e; do
    [ -z "$h" ] || c=$(printf '%s' "$h" | xxd -r -p)
    printf '%s\t%s\n' "$c" "$e"
  done)
[ -n "$rows" ] || quiet
# Sorted by count desc, then name, so the body is deterministic.
body=$(printf '%s\n' "$rows" |
  awk -F'\t' '{n[$1]++; if ($2 != 0) f[$1]++} END {for (c in n) printf "%d\t%s\t%d\n", n[c], c, f[c]}' |
  LC_ALL=C sort -t$'\t' -k1,1nr -k2,2 | awk -F'\t' '{printf "%dx %s (%d failed)\n", $1, $2, $3}')
total=$(printf '%s\n' "$rows" | wc -l)

# CURL overrides the binary so tests can inject a stub.
if printf '%s\n' "$body" | "${CURL:-curl}" -fsS -H "Authorization: Bearer ${NTFY_TOKEN:-}" \
  -H "Title: Jerry box: $total processes" --data-binary @- "$NTFY_URL/$NTFY_TOPIC"; then
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '%s\n' "$cursor" >"$STATE_FILE"
else
  echo "jerry-report: ntfy POST failed, will retry next run" >&2
fi
