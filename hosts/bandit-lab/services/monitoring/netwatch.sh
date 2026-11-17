# New-device watcher: page ntfy once for a MAC on the home LAN uplink that was
# never seen before. $STATE_DIRECTORY/known-macs grows monotonically; the first
# run bootstraps it silently so the whole LAN does not alarm at once.
# ip/jq/curl come from PATH (netwatch.nix pins them; the test shims ip and curl).
set -euo pipefail

iface=${NETWATCH_IFACE:-enp44s0}
state="$STATE_DIRECTORY/known-macs"

# Reachable neighbours only: FAILED/INCOMPLETE entries carry no usable MAC.
current=$(ip -j neigh show dev "$iface" | jq -r '
  .[]
  | select(.lladdr != null)
  | select([(.state // [])[] | . == "FAILED" or . == "INCOMPLETE"] | any | not)
  | "\(.lladdr) \(.dst)"')

if [ ! -e "$state" ]; then
  printf '%s\n' "$current" | awk 'NF {print $1}' >"$state"
  exit 0
fi

printf '%s\n' "$current" | while read -r mac dst; do
  [ -n "$mac" ] || continue
  grep -qxF "$mac" "$state" && continue
  # Record only on a successful send, so a failed push is retried next run.
  if curl -fsS -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: Neues Gerät" \
    -d "Neues Gerät im Heimnetz: $mac $dst" "$NTFY_URL/$NTFY_TOPIC" >/dev/null; then
    echo "$mac" >>"$state"
  fi
done
