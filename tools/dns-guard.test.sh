#!/usr/bin/env bash
# Test for tools/dns-guard.sh with stub commands first on PATH.
# Run: tools/dns-guard.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export GUARD_TEST_DIR=$t
mkdir "$t/stub"
stub() { cat >"$t/stub/$1"; chmod +x "$t/stub/$1"; } # stub <name>: stdin is the script

# dig: pops the next word of $t/seq (ok|nx|servfail|timeout) and answers like dig would.
stub dig <<'EOF'
#!/usr/bin/env bash
d=$GUARD_TEST_DIR
echo "$*" >>"$d/dig.log"
w=$(head -n1 "$d/seq"); sed -i 1d "$d/seq"
case $w in
  ok) echo ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1' ;;
  nx) echo ';; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 1' ;;
  servfail) echo ';; ->>HEADER<<- opcode: QUERY, status: SERVFAIL, id: 1' ;;
  *) echo ';; connection timed out; no servers could be reached'; exit 9 ;;
esac
EOF
# tailscale: logs args; fails while $t/ts-fail holds a number > 0.
stub tailscale <<'EOF'
#!/usr/bin/env bash
d=$GUARD_TEST_DIR
echo "$*" >>"$d/ts.log"
n=$(cat "$d/ts-fail" 2>/dev/null || echo 0)
if ((n > 0)); then echo $((n - 1)) >"$d/ts-fail"; exit 1; fi
EOF
stub resolvectl <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$GUARD_TEST_DIR/rv.log"
EOF
# sleep: ends the endless loop after one tick per seq word.
stub sleep <<'EOF'
#!/usr/bin/env bash
d=$GUARD_TEST_DIR
n=$(($(cat "$d/n") + 1)); echo "$n" >"$d/n"
((n >= $(cat "$d/total"))) && kill -TERM "$PPID"
exit 0
EOF
export PATH="$t/stub:$PATH"

# run <words…>: one probe result per tick; runs the guard like writeShellApplication does (errexit, nounset, pipefail).
run() {
  printf '%s\n' "$@" >"$t/seq"; echo $# >"$t/total"; echo 0 >"$t/n"
  : >"$t/dig.log"; : >"$t/ts.log"; : >"$t/rv.log"
  { timeout 10 bash -euo pipefail "$here/dns-guard.sh" >"$t/out.log" 2>&1; } 2>/dev/null || true # 2>/dev/null: hide bash's "Terminated" note
  [[ $(wc -l <"$t/dig.log") == "$#" ]] || { echo "FAIL: guard stopped early ($*)" >&2; cat "$t/out.log" >&2; exit 1; }
}
lines() { printf '%s\n' "$@"; } # expected file content, one arg per line

# unknown start sets
run ok ok
diff <(lines 'set --accept-dns=true') "$t/ts.log"
diff <(lines flush-caches) "$t/rv.log"
grep -q 'accept-dns=true' "$t/out.log"

# no repeat set
run ok ok ok ok
diff <(lines 'set --accept-dns=true') "$t/ts.log"

# alternating no switch
run ok ok timeout ok timeout ok
diff <(lines 'set --accept-dns=true') "$t/ts.log"

# fallback and back
run ok ok timeout timeout ok ok
diff <(lines 'set --accept-dns=true' 'set --accept-dns=false' 'set --accept-dns=true') "$t/ts.log"
diff <(lines flush-caches flush-caches flush-caches) "$t/rv.log"
grep -q 'unreachable.*accept-dns=false' "$t/out.log"

# servfail is fail
run servfail servfail
diff <(lines 'set --accept-dns=false') "$t/ts.log"

# nxdomain is ok
run nx nx
diff <(lines 'set --accept-dns=true') "$t/ts.log"

# set fails retries
echo 1 >"$t/ts-fail"
run ok ok ok
diff <(lines 'set --accept-dns=true' 'set --accept-dns=true') "$t/ts.log"
diff <(lines flush-caches) "$t/rv.log"

# timeout keeps running (run checks 3 dig calls) and probe args
run timeout timeout timeout
while read -r line; do
  [[ $line == *+time=1* && $line == *+tries=1* && $line == *@100.125.161.81* ]] || { echo "FAIL: dig args: $line" >&2; exit 1; }
  grep -qE '(^| )p[0-9]+\.example\.com( |$)' <<<"$line" || { echo "FAIL: probe name: $line" >&2; exit 1; }
done <"$t/dig.log"
[[ $(sed -n 1p "$t/dig.log") != $(sed -n 2p "$t/dig.log") ]] || { echo "FAIL: probe name repeats" >&2; exit 1; }

echo ok
