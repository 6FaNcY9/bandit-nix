#!/bin/sh
# Offline tests for the pong bootstrap scripts. Run from Termux: sh hosts/pong/bootstrap/tests/run.sh
# They never mount, download or touch /data/nix-root.
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
# Fake su for tests: claims root for the id check, runs everything else as this user.
printf '#!/bin/sh\n[ "$2" = "id -u" ] && { echo 0; exit 0; }\nshift; exec sh -c "$@"\n' > "$tmp/fakesu"
chmod +x "$tmp/fakesu"
ok() { pass=$((pass + 1)); echo "PASS $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1: $2"; }

# hide-check: a clean mountinfo passes
printf '22 1 0:20 / / rw - ext4 /dev/root rw\n' > "$tmp/clean"
out=$(PONG_NIX_ROOT=/data/nix-root sh "$here/pong-hide-check" "$tmp/clean" 2>&1)
[ $? -eq 0 ] && [ "$out" = "OK hidden" ] && ok hide_clean || no hide_clean "$out"

# hide-check: a visible chroot mount fails and names the file
printf '22 1 0:20 / / rw - ext4 /dev/root rw\n90 22 0:5 / /data/nix-root/proc rw - proc proc rw\n' > "$tmp/leak"
out=$(PONG_NIX_ROOT=/data/nix-root sh "$here/pong-hide-check" "$tmp/clean" "$tmp/leak" 2>&1)
rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q "$tmp/leak" && ok hide_leak || no hide_leak "rc=$rc $out"

# hide-check: an unreadable file is a failure, not a silent pass
out=$(PONG_NIX_ROOT=/data/nix-root sh "$here/pong-hide-check" "$tmp/missing" 2>&1)
[ $? -eq 1 ] && ok hide_unreadable || no hide_unreadable "$out"

# enter: no root gives exit 2 and the message, quickly
start=$(date +%s)
out=$(PONG_SU=false PONG_NIX_ROOT="$tmp/root" sh "$here/pong-nix-enter" true 2>&1)
rc=$?
[ $rc -eq 2 ] && [ "$out" = "pong-nix: no root" ] && [ $(($(date +%s) - start)) -le 2 ] && ok enter_noroot || no enter_noroot "rc=$rc $out"

# enter: root works but no chroot installed gives exit 2 with a reason
out=$(PONG_SU="$tmp/fakesu" PONG_NIX_ROOT="$tmp/none" sh "$here/pong-nix-enter" true 2>&1)
rc=$?
[ $rc -eq 2 ] && echo "$out" | grep -q "not installed" && ok enter_missing || no enter_missing "rc=$rc $out"

# enter: an installed root is detected although .nix-profile is absolute (valid only inside)
mkdir -p "$tmp/inst/nix/store" "$tmp/inst/home/vino"
ln -s /home/vino/.local/state/nix/profiles/profile "$tmp/inst/home/vino/.nix-profile"
out=$(PONG_SU="$tmp/fakesu" PONG_NIX_ROOT="$tmp/inst" sh "$here/pong-nix-enter" true 2>&1)
echo "$out" | grep -q "not installed" && no enter_installed "$out" || ok enter_installed

# install: refuses a non-empty target and downloads nothing
mkdir -p "$tmp/full" && touch "$tmp/full/x"
out=$(PONG_SU="$tmp/fakesu" PONG_NIX_ROOT="$tmp/full" sh "$here/pong-nix-install" 2>&1)
rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q "not empty" && ok install_refuses || no install_refuses "rc=$rc $out"

echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
