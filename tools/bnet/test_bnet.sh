#!/bin/sh
# sh tools/bnet/test_bnet.sh  — ssh and curl are stubbed; nothing leaves this machine.
set -u
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
cat > "$t/bin/ssh" <<'S'
#!/bin/sh
if [ "$1" = -n ]; then shift; else cat > /dev/null; fi   # like real ssh: eats stdin unless given -n
echo "ssh $*" >> "$BNET_TEST_LOG"
target=$1; shift
case "$target $*" in *"$BNET_TEST_MSG_FAILS"*msg*) exit 1 ;; esac
echo "out from $target"
S
cat > "$t/bin/curl" <<'S'
#!/bin/sh
[ -n "${BNET_TEST_ROUTER_DOWN:-}" ] && exit 7
cat "$BNET_TEST_DEVICES"
S
chmod +x "$t/bin/ssh" "$t/bin/curl"
cat > "$t/hosts" <<'S'
# name   ssh target          groups
albert   admin@100.98.68.118 pcs
slayer   admin@100.76.40.98  pcs
pong     pong                phones
S
echo '[{"host":"albert","kind":"pc","online":true,"state":"light","job":null},{"host":"slayer","kind":"pc","online":true,"state":"idle","job":null}]' > "$t/dev1"
echo '[{"host":"albert","kind":"pc","online":true,"state":"light","job":null},{"host":"slayer","kind":"pc","online":true,"state":"heavy","job":null}]' > "$t/dev2"
export PATH="$t/bin:$PATH" BNET_HOSTS="$t/hosts" BNET_TOKEN=x BNET_NOTICE_WAIT=0 BNET_TEST_LOG="$t/log" BNET_TEST_DEVICES="$t/dev1" BNET_TEST_MSG_FAILS=none
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

: > "$t/log"
BNET_TEST_DEVICES="$t/dev2" sh "$here/bnet" run --disruptive pcs -- shutdown /r >/dev/null
check 'two busy PCs both get the notice' '[ "$(grep -c " msg " "$t/log")" = 2 ]'

: > "$t/log"
BNET_TEST_ROUTER_DOWN=1 sh "$here/bnet" run --disruptive pcs -- shutdown /r >/dev/null 2>&1
check 'unknown state (router down) means everyone gets the notice' '[ "$(grep -c " msg " "$t/log")" = 2 ]'

: > "$t/log"
BNET_TEST_DEVICES="$t/dev2" BNET_TEST_MSG_FAILS=100.76.40.98 sh "$here/bnet" run --disruptive pcs -- shutdown /r >/dev/null 2>&1
check 'a PC whose notice failed is skipped' '! grep -q "100.76.40.98 shutdown" "$t/log" && grep -q "100.98.68.118 shutdown" "$t/log"'

sh "$here/bnet" run nosuchhost -- true 2>/dev/null; code=$?
check 'unknown host exits 2' '[ "$code" = 2 ]'

out=$(sh "$here/bnet" status)
check 'status shows each device and its state' 'echo "$out" | grep -q "albert.*light" && echo "$out" | grep -q "slayer.*idle"'
exit $fail
