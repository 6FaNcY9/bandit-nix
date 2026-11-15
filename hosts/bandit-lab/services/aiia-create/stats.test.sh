#!/usr/bin/env bash
# Laptop test for stats.sh against a throwaway redis-server:
#   nix shell nixpkgs#redis nixpkgs#curl -c bash stats.test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
port=$((20000 + RANDOM % 20000))
redis-server --port "$port" --bind 127.0.0.1 --save '' --appendonly no --dir "$t" --daemonize yes --pidfile "$t/redis.pid" >/dev/null
trap 'kill "$(cat "$t/redis.pid")" 2>/dev/null; rm -rf "$t"' EXIT
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
r() { redis-cli -p "$port" "$@" >/dev/null; }
until redis-cli -p "$port" ping >/dev/null 2>&1; do sleep 0.1; done
mkdir "$t/out"
export AIIA_TEXTFILE_DIR=$t/out AIIA_REDIS_CLI="redis-cli -p $port" AIIA_HEALTHZ_URL=http://127.0.0.1:1/healthz
run() { bash "$here/stats.sh"; }
val() { awk -v m="$1" '$1 == m {print $2}' "$t/out/aiia-stats.prom"; }

# Empty Redis: all zero, nothing missing.
run || fail "empty run failed"
[ "$(val aiia_designs)" = 0 ] && [ "$(val aiia_site_generations)" = 0 ] && [ "$(val 'aiia_orders{state="waiting"}')" = 0 ] || fail "empty counts"

u1=0123456789abcdef0123456789abcdef u2=fedcba9876543210fedcba9876543210
r hset "user:$u1" email canary-mail@example.org name CANARY-NAME
r hset "user:$u2" email b@example.org
r set "user:email:canary-mail@example.org" "$u1"
r sadd "user:$u1:likes" d1
r hset design:aa01 id aa01 user_id "$u1"
r hset design:aa02 id aa02 user_id ""
r hset design:aa03 id aa03
r sadd design:aa01:likers "$u2"
r hset design:aa01:liked_at "$u2" 1
r hset design:aa01:likes:week "$u2" w
r zadd designs:user:"$u1" 1 aa01
r zadd reports:open 1 aa02
r zadd orders:waiting 1 o1 2 o2
r zadd orders:shipped 1 o3
r set quota:site 4
r set "quota:ip:203.0.113.9" 1

run || fail "seeded run failed"
[ "$(val aiia_accounts)" = 2 ] || fail "accounts: $(val aiia_accounts)"
[ "$(val aiia_designs)" = 3 ] || fail "designs: $(val aiia_designs)"
[ "$(val aiia_designs_account)" = 1 ] || fail "account designs: $(val aiia_designs_account)"
[ "$(val aiia_reports_open)" = 1 ] || fail "reports"
[ "$(val aiia_site_generations)" = 4 ] || fail "quota"
[ "$(val 'aiia_orders{state="waiting"}')" = 2 ] && [ "$(val 'aiia_orders{state="shipped"}')" = 1 ] && [ "$(val 'aiia_orders{state="cancelled"}')" = 0 ] || fail "orders"
[ "$(val aiia_stats_last_success_timestamp_seconds)" -gt 0 ] || fail "timestamp"
grep -q '^aiia_healthz_ok 0$' "$t/out/aiia-healthz.prom" || fail "closed healthz port not reported as 0"
# Aggregates only: no address, name, id or IP in any output.
! grep -rqE "@|CANARY|$u1|$u2|aa01|203\.0" "$t/out" || fail "personal value in metrics"

# Redis down: the run fails, keeps the old numbers (the stale alert fires) and still writes healthz.
before=$(cat "$t/out/aiia-stats.prom")
rm "$t/out/aiia-healthz.prom"
AIIA_REDIS_CLI="redis-cli -p 1" run 2>/dev/null && fail "run with Redis down succeeded"
[ "$(cat "$t/out/aiia-stats.prom")" = "$before" ] || fail "failed run changed the numbers"
[ -e "$t/out/aiia-healthz.prom" ] || fail "healthz not written when Redis is down"
echo "stats.test.sh: ok"
