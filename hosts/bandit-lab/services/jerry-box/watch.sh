# Stdin filter: `jerry-watch ssh|restic` posts one ntfy message per matching line.
# CURL overrides the binary so tests can inject a stub.
NTFY_URL=${NTFY_URL:-http://127.0.0.1:2586}
NTFY_TOPIC=${NTFY_TOPIC:-mcbots}
DEBOUNCE_SECONDS=${DEBOUNCE_SECONDS:-600}
mode=${1:?usage: jerry-watch ssh|restic}
last_sent=0

post() {
  "${CURL:-curl}" -fsS --max-time 10 -H "Authorization: Bearer ${NTFY_TOKEN:-}" -H "Title: $1" \
    --data-raw "$2" "$NTFY_URL/$NTFY_TOPIC" || echo "ntfy post failed" >&2
}

while IFS= read -r line; do
  case $mode in
    ssh)
      case $line in *"Accepted publickey"*) post "Jerry box: ssh login" "$line" ;; esac
      ;;
    restic)
      case $line in
        *jerry*POST* | *POST*jerry*)
          now=$(date +%s)
          if [ $((now - last_sent)) -ge "$DEBOUNCE_SECONDS" ]; then
            last_sent=$now
            post "Jerry restic: backup activity" "$line"
          fi
          ;;
      esac
      ;;
    *) echo "unknown mode: $mode" >&2; exit 2 ;;
  esac
done

# The journal stream must never end: fail so Restart=on-failure revives the unit.
echo "jerry-watch: input ended" >&2
exit 1
