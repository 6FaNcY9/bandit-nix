#!/usr/bin/env bash
# Test for the raw tools/waybar-*.sh scripts with stub commands first on PATH.
# Run: tools/waybar.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# Stub commands, each steered per call by an env var: VPN=tun|none, TS=up|none, GETENT=block|real|hang,
# STREAM=on|off (default off), MAKO=ok|fail. makoctl/pkill/notify-send log their args, wl-copy keeps its stdin.
export BAR_TEST_DIR=$t
mkdir "$t/stub"
stub() { cat >"$t/stub/$1"; chmod +x "$t/stub/$1"; } # stub <name>: stdin is the script
chk() { jq -e "$1" >/dev/null || { echo "FAIL at line ${BASH_LINENO[0]}: $1" >&2; exit 1; }; } # chk <jq filter>: JSON on stdin, silent assert
stub ip <<'EOF'
#!/usr/bin/env bash
# ip -4 -j addr [show dev X]: lo and eth0 always, tun0 / tailscale0 on request
dev=; [[ ${4:-} == show && ${5:-} == dev ]] && dev=$6
jq -c --arg dev "$dev" --arg vpn "${VPN:-tun}" --arg ts "${TS:-up}" -n '
  def d($n; $ip): {ifname: $n, addr_info: [{family: "inet", local: $ip}]};
  [d("lo"; "127.0.0.1"), d("eth0"; "192.168.1.20")]
  + (if $vpn == "tun" then [d("tun0"; "10.10.14.7")] else [] end)
  + (if $ts == "up" then [d("tailscale0"; "100.64.0.5")] else [] end)
  | map(select($dev == "" or .ifname == $dev))'
EOF
stub getent <<'EOF'
#!/usr/bin/env bash
case ${GETENT:-block} in
  block) echo '0.0.0.0         STREAM doubleclick.net' ;;
  real) echo '142.250.185.66  STREAM doubleclick.net' ;;
  hang) exec sleep 10 ;;
esac
EOF
stub waybar-stream <<'EOF'
#!/usr/bin/env bash
[[ ${STREAM:-off} == on ]]
EOF
stub makoctl <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$BAR_TEST_DIR/mako"
[[ ${MAKO:-ok} == ok ]]
EOF
stub pkill <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$BAR_TEST_DIR/pkill"
EOF
stub wl-copy <<'EOF'
#!/usr/bin/env bash
cat >"$BAR_TEST_DIR/clip"
EOF
stub notify-send <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$BAR_TEST_DIR/notify"
EOF
export PATH=$t/stub:$PATH
mkdir "$t/run"

ai() { BAR_AI_FILE=$t/u.json BAR_NOW=1794880000 bash "$here/waybar-ai.sh"; }
tg() { BAR_PENTEST_SESSION=$t/ps XDG_RUNTIME_DIR=$t/run bash "$here/waybar-target.sh" "$@"; }
st() { XDG_RUNTIME_DIR=$t/run bash "$here/waybar-stream.sh" "$@"; }
dns() { bash "$here/waybar-dns.sh" "$@"; }

# --- waybar-ai: weekly limit from the claude-hud snapshot; BAR_NOW 1794880000 = 2026-11-17T01:46:40Z
snap() { jq -n --argjson p "$1" --arg u "$2" '{updated_at:$u, five_hour:{used_percentage:12, resets_at:"2026-11-17T02:00:00Z"}, seven_day:{used_percentage:$p, resets_at:"2026-11-20T08:00:00Z"}}' >"$t/u.json"; }
now=$(date -u -d @1794880000 +%FT%TZ)
snap 68 "$now";  chk '.text == "AI ▰▰▰▰▰▰▰▱▱▱ 68%" and .class == "ok"' <<<"$(ai)"
snap 80 "$now";  chk '.class == "warn"' <<<"$(ai)"
snap 95 "$now";  chk '.class == "crit"' <<<"$(ai)"
snap 68 "$(date -u -d @$((1794880000 - 601)) +%FT%TZ)"; chk '.class == "stale"' <<<"$(ai)"
chk '.tooltip | test("Woche 68 % · reset in ") and test("5 h 12 % · reset in ")' <<<"$(ai)"
snap 68 "$now";  chk '.tooltip == "Woche 68 % · reset in 3d 6h\n5 h 12 % · reset in 0h 13m"' <<<"$(ai)"  # Xd Yh, Xh Ym
snap 68 "${now%Z}.123Z"; chk '.class == "ok"' <<<"$(ai)"                   # JS toISOString has milliseconds
rm "$t/u.json"; chk '.text == ""' <<<"$(ai)"
echo '{"seven_day":{"used_percentage":null}}' >"$t/u.json"; chk '.text == ""' <<<"$(ai)"
echo garbage >"$t/u.json"; chk '.text == ""' <<<"$(ai)"

# --- waybar-target: VPN (first tun* IPv4) → pt target (last target= line of the session file)
printf 'engagement=x\r\ntarget=10.10.11.5\r\n' >"$t/ps"                              # CRLF tolerated
chk '.text | test("10.10.14.7") and test("10.10.11.5") and test("→")' <<<"$(tg)"
chk '.tooltip == "VPN 10.10.14.7\nZiel 10.10.11.5"' <<<"$(tg)"
printf 'target=old\ntarget=10.10.11.5\n' >"$t/ps"; chk '.text | test("old") | not' <<<"$(tg)"   # last target= wins
echo 'target=a&b<c>' >"$t/ps"; chk '.text | test("a&amp;b&lt;c&gt;")' <<<"$(tg)"       # pango escape
rm "$t/ps"; chk '.text | test("10.10.14.7") and (test("→") | not)' <<<"$(tg)"       # VPN only
chk '.tooltip == "VPN 10.10.14.7"' <<<"$(tg)"
echo 'target=10.10.11.5' >"$t/ps"; chk '(.text | test("10.10.11.5") and (test("10.10.14") | not) and (test("→") | not))' <<<"$(VPN=none tg)"  # target only
rm "$t/ps"; chk '.text == ""' <<<"$(VPN=none tg)"                                   # neither: hidden
echo 'scope=a' >"$t/ps"; chk '.text == ""' <<<"$(VPN=none tg)"                      # no target= line
echo 'target=10.10.11.5' >"$t/ps"; chk '(.text | test("10\\.") | not) and (.text | test("•••")) and (.tooltip | test("10\\.") | not)' <<<"$(STREAM=on tg)"
tg copy target; [[ $(cat "$t/clip") == 10.10.11.5 ]]; grep -q 'Target copied 10.10.11.5' "$t/notify"
tg copy vpn; [[ $(cat "$t/clip") == 10.10.14.7 ]]
: >"$t/notify"; STREAM=on tg copy vpn; [[ $(cat "$t/clip") == 10.10.14.7 ]]; [[ -s $t/notify && $(<"$t/notify") != *10.10.14.7* ]]  # copies the real IP, notification masked
rm "$t/ps"; if tg copy target; then false; fi; grep -q 'no address' "$t/notify"       # empty: notify + exit 1
if VPN=none tg copy vpn; then false; fi
rc=0; tg copy bogus 2>/dev/null || rc=$?; [[ $rc == 2 ]]

echo ok
