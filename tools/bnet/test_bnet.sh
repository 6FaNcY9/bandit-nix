#!/bin/sh
# sh tools/bnet/test_bnet.sh  — ssh and curl are stubbed; nothing leaves this machine.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
cat > "$t/bin/ssh" <<'S'
#!/bin/sh
echo "ssh $*" >> "$BNET_TEST_LOG"
target=$1; shift
echo "out from $target"
S
cat > "$t/bin/curl" <<'S'
#!/bin/sh
echo '[{"host":"albert","kind":"pc","online":true,"state":"light","job":null},{"host":"slayer","kind":"pc","online":true,"state":"idle","job":null}]'
S
chmod +x "$t/bin/ssh" "$t/bin/curl"
cat > "$t/hosts" <<'S'
# name   ssh target          groups
albert   admin@100.98.68.118 pcs
slayer   admin@100.76.40.98  pcs
pong     pong                phones
S
export PATH="$t/bin:$PATH" BNET_HOSTS="$t/hosts" BNET_TOKEN=x BNET_NOTICE_WAIT=0 BNET_TEST_LOG="$t/log"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

out=$(sh "$here/bnet" run pcs -- hostname)
check 'group pcs runs on albert and slayer' '[ "$(grep -c "^ssh admin@" "$t/log")" = 2 ]'
check 'output lines are prefixed with the host' 'echo "$out" | grep -q "^\[albert\] out from admin@100.98.68.118" && echo "$out" | grep -q "^\[slayer\] "'

: > "$t/log"
sh "$here/bnet" run --disruptive pcs -- shutdown /r >/dev/null
check 'a light PC gets the notice before the command' \
  '[ "$(sed -n 1p "$t/log" | grep -c "admin@100.98.68.118 msg")" = 1 ] && grep -n "admin@100.98.68.118 shutdown" "$t/log" | grep -qv "^1:"'
check 'an idle PC gets no notice' '! grep -q "admin@100.76.40.98 msg" "$t/log"'

sh "$here/bnet" run nosuchhost -- true 2>/dev/null; code=$?
check 'unknown host exits 2' '[ "$code" = 2 ]'

out=$(sh "$here/bnet" status)
check 'status shows each device and its state' 'echo "$out" | grep -q "albert.*light" && echo "$out" | grep -q "slayer.*idle"'
exit $fail
