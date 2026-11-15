#!/usr/bin/env bash
# aiia-create usage numbers for Grafana, as node-exporter textfile metrics.
# Privacy: only counts leave this script. Key names (random ids) pass through
# pipes to be counted; they are never written, logged or used as labels, and
# no field value of a record is read (HSTRLEN returns a length only).
# Env: AIIA_TEXTFILE_DIR (required), AIIA_REDIS_CLI (redis-cli command),
# AIIA_HEALTHZ_URL.
set -euo pipefail
dir=${AIIA_TEXTFILE_DIR:?}
read -ra cli <<<"${AIIA_REDIS_CLI:-podman exec -i aiia-create-redis redis-cli}"
healthz=${AIIA_HEALTHZ_URL:-http://127.0.0.1:3080/healthz}
r() { "${cli[@]}" "$@"; }
# Atomic, so node-exporter never reads half a file.
put() { printf '%s' "$2" >"$dir/.$1.tmp" && mv "$dir/.$1.tmp" "$dir/$1"; }
num() { [[ $1 =~ ^[0-9]+$ ]] || {
  echo "aiia-stats: unexpected Redis reply for $2" >&2
  exit 1
}; }

# Written first and on every run: a Redis failure must not hide the web check.
code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$healthz" || true)
ok=0
[ "$code" = 200 ] && ok=1
put aiia-healthz.prom "# HELP aiia_healthz_ok 1 if the local aiia web healthz answered 200.
# TYPE aiia_healthz_ok gauge
aiia_healthz_ok $ok
"

# SCAN, never KEYS. Assignments keep set -e on a Redis failure; the grep
# that finds nothing must not count as one.
keys=$(r --scan --pattern 'user:*')
accounts=$(grep -cE '^user:[0-9a-f]{32}$' <<<"$keys" || true)
keys=$(r --scan --pattern 'design:*')
designs=$(grep -E '^design:[0-9a-f]+$' <<<"$keys" || true) # not the :likers etc. siblings
total=0 owned=0
if [ -n "$designs" ]; then
  total=$(grep -c . <<<"$designs")
  owned=$(sed 's/.*/HSTRLEN & user_id/' <<<"$designs" | r | awk '$1 ~ /^[0-9]+$/ && $1 > 0 {n++} END {print n + 0}')
fi

states=(waiting in_production shipped rejected cancelled)
mapfile -t v < <(printf '%s\n' "ZCARD reports:open" "GET quota:site" "${states[@]/#/ZCARD orders:}" | r)
[ "${#v[@]}" -eq $((2 + ${#states[@]})) ] || {
  echo "aiia-stats: short Redis reply" >&2
  exit 1
}
v[1]=${v[1]:-0} # no generation in the current window: the key is absent
for n in "$accounts" "$total" "$owned" "${v[@]}"; do num "$n" counts; done

out="# HELP aiia_accounts Accounts (user records).
# TYPE aiia_accounts gauge
aiia_accounts $accounts
# HELP aiia_designs Stored designs (anonymous ones expire after 30 days, account ones after 365).
# TYPE aiia_designs gauge
aiia_designs $total
# HELP aiia_designs_account Stored designs that belong to an account.
# TYPE aiia_designs_account gauge
aiia_designs_account $owned
# HELP aiia_reports_open Reported designs waiting for a decision.
# TYPE aiia_reports_open gauge
aiia_reports_open ${v[0]}
# HELP aiia_site_generations Generations started in the current site quota window.
# TYPE aiia_site_generations gauge
aiia_site_generations ${v[1]}
# HELP aiia_orders Orders per state.
# TYPE aiia_orders gauge
"
for i in "${!states[@]}"; do out+="aiia_orders{state=\"${states[i]}\"} ${v[i + 2]}
"; done
out+="# HELP aiia_stats_last_success_timestamp_seconds When these numbers were collected.
# TYPE aiia_stats_last_success_timestamp_seconds gauge
aiia_stats_last_success_timestamp_seconds $(date +%s)
"
put aiia-stats.prom "$out"
