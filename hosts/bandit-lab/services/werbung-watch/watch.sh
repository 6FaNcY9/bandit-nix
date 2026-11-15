# Phone reminders while the Bandit Anarchy Discord looks for its first testers, over ntfy.
#   werbung-watch bump     "time for /bump" (Disboard), until the Discord has STOP_AT members
#   werbung-watch members  ntfy when the member count went up since the last run
# Disboard and Discord forbid automated bumping, so this only reminds; the owner bumps.
NTFY_URL=${NTFY_URL:-http://127.0.0.1:2586}
NTFY_TOPIC=${NTFY_TOPIC:-mcbots}
STATE_FILE=${STATE_FILE:-/var/lib/werbung-watch/members}
INVITE=${INVITE:-gztQRPwkvj}
STOP_AT=${STOP_AT:-8}

# CURL overrides the binary so tests can inject a stub.
if ! count=$("${CURL:-curl}" -fsS -A "werbung-watch (bandit-lab)" \
  "https://discord.com/api/v10/invites/$INVITE?with_counts=true" | jq -er '.approximate_member_count'); then
  echo "werbung-watch: invite lookup failed, next run tries again" >&2
  exit 0
fi

send() {
  "${CURL:-curl}" -fsS -H "Authorization: Bearer ${NTFY_TOKEN:-}" -H "Title: $1" \
    --data-raw "$2" "$NTFY_URL/$NTFY_TOPIC" >/dev/null
}

case "${1:-}" in
bump)
  [ "$count" -lt "$STOP_AT" ] || exit 0
  send "Disboard: Zeit fuer /bump" "Schreib /bump im Discord Bandit Anarchy. Mitglieder: $count" ||
    echo "werbung-watch: ntfy POST failed" >&2
  ;;
members)
  last=$(cat "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$last" ] && [ "$count" -gt "$last" ]; then
    # Keep the old count on a failed POST so the next run alerts again.
    send "Discord: neues Mitglied" "Bandit Anarchy hat jetzt $count Mitglieder (vorher $last). Schau in #hilfe." || {
      echo "werbung-watch: ntfy POST failed, will retry next run" >&2
      exit 0
    }
  fi
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '%s\n' "$count" >"$STATE_FILE"
  ;;
*)
  echo "usage: werbung-watch bump|members" >&2
  exit 2
  ;;
esac
