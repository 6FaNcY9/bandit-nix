#!/usr/bin/env bash
# Laptop test for netwatch.sh: feed `ip -j neigh` fixtures through it with `ip`
# and `curl` shimmed on PATH, and check the bootstrap/new-device/ignore logic.
#   nix shell nixpkgs#jq -c sh netwatch.test.sh   (jq must be on PATH)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

mkdir "$t/bin" "$t/state" "$t/calls"
# ip shim: ignore the args, print the fixture the test currently points at.
cat >"$t/bin/ip" <<'EOF'
#!/bin/sh
cat "$IP_FIXTURE"
EOF
# curl shim: record each call (args + -d body) to one calls/call-N file; always succeed.
cat >"$t/bin/curl" <<'EOF'
#!/bin/sh
n=$(ls "$CALLS_DIR" | wc -l)
body=""
prev=""
for a in "$@"; do
  [ "$prev" = "-d" ] && body="$a"
  prev="$a"
done
{ printf '%s\n' "$@"; echo ---; printf '%s\n' "$body"; } >"$CALLS_DIR/call-$n"
exit 0
EOF
chmod +x "$t/bin/ip" "$t/bin/curl"

export PATH="$t/bin:$PATH"
export STATE_DIRECTORY="$t/state" CALLS_DIR="$t/calls"
export NTFY_URL=http://127.0.0.1:2586 NTFY_TOPIC=mcbots NTFY_TOKEN=test-token

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
calls() { ls "$CALLS_DIR" | wc -l | tr -d ' '; }
run() { bash "$here/netwatch.sh"; }

mac1=aa:bb:cc:00:00:01 mac2=aa:bb:cc:00:00:02 mac3=aa:bb:cc:00:00:03
macNew=aa:bb:cc:00:00:99 macBad=aa:bb:cc:00:00:66

# Fixture 1: three reachable neighbours.
cat >"$t/f1.json" <<EOF
[
  {"dst":"192.168.0.11","lladdr":"$mac1","state":["REACHABLE"]},
  {"dst":"192.168.0.12","lladdr":"$mac2","state":["STALE"]},
  {"dst":"192.168.0.13","lladdr":"$mac3","state":["REACHABLE"]}
]
EOF
export IP_FIXTURE="$t/f1.json"

# First run: bootstrap -> records 3 MACs, sends nothing.
run || fail "first run failed"
[ "$(calls)" = 0 ] || fail "bootstrap sent $(calls) message(s), expected 0"
[ "$(wc -l <"$STATE_DIRECTORY/known-macs")" -eq 3 ] || fail "bootstrap did not record 3 MACs"

# Fixture 2: the same three plus one new MAC, plus FAILED (no lladdr) and
# INCOMPLETE (with an lladdr) entries that must be ignored.
cat >"$t/f2.json" <<EOF
[
  {"dst":"192.168.0.11","lladdr":"$mac1","state":["REACHABLE"]},
  {"dst":"192.168.0.12","lladdr":"$mac2","state":["STALE"]},
  {"dst":"192.168.0.13","lladdr":"$mac3","state":["REACHABLE"]},
  {"dst":"192.168.0.99","lladdr":"$macNew","state":["REACHABLE"]},
  {"dst":"192.168.0.77","state":["FAILED"]},
  {"dst":"192.168.0.66","lladdr":"$macBad","state":["INCOMPLETE"]}
]
EOF
export IP_FIXTURE="$t/f2.json"

# Second run: exactly one message, containing the new MAC.
run || fail "second run failed"
[ "$(calls)" = 1 ] || fail "second run sent $(calls) message(s), expected 1"
grep -rqF "$macNew" "$CALLS_DIR" || fail "message did not contain the new MAC"
# The ignored INCOMPLETE entry must neither alert nor be recorded.
! grep -qF "$macBad" "$STATE_DIRECTORY/known-macs" || fail "INCOMPLETE MAC recorded"

# Third identical run: the new MAC is now known -> nothing more sent.
run || fail "third run failed"
[ "$(calls)" = 1 ] || fail "third run sent extra messages (total $(calls))"

echo "netwatch.test.sh: ok"
