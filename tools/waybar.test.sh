#!/usr/bin/env bash
# Test for the raw tools/waybar-*.sh scripts with stub commands first on PATH.
# Run: tools/waybar.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# Stub commands, each steered per call by an env var: VPN=tun|none, TS=up|none, GETENT=block|real|hang,
# STREAM=on|off (default off), MAKO=ok|fail. makoctl/pkill/notify-send log their args, wl-copy keeps its stdin.
# makoctl also keeps a mode list in $t/modes like mako 1.11: `mode` lists, `-a X` appends without a duplicate check, `-r X` removes one entry.
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
[[ ${MAKO:-ok} == ok ]] || exit 1
m=$BAR_TEST_DIR/modes
case ${1:-}:${2:-} in
  mode:) cat "$m" ;;
  mode:-a) echo "$3" >>"$m" ;;
  mode:-r) awk -v x="$3" '!d && $0 == x {d = 1; next} {print}' "$m" >"$m.new"; mv "$m.new" "$m" ;;
esac
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
dns() { bash "$here/waybar-dns.sh"; }

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
echo 'target=10.10.11.5' >"$t/ps"; [[ $(tg get) == $'10.10.14.7\n10.10.11.5' ]]
[[ $(STREAM=on tg get) == $'10.10.14.7\n10.10.11.5' ]]              # raw: the caller masks
rm "$t/ps"; [[ $(VPN=none tg get | wc -l) == 2 && -z $(VPN=none tg get | tr -d '\n') ]]  # both empty, still 2 lines

# --- waybar-stream: flag files in $XDG_RUNTIME_DIR, mako mode "stream", Waybar signal 8
fresh() { rm -rf "$t/run"; mkdir "$t/run"; : >"$t/mako"; : >"$t/pkill"; : >"$t/modes"; }
nr() { env -u XDG_RUNTIME_DIR bash "$here/waybar-stream.sh" "$@"; }
fresh
if st status; then false; fi                                                       # off at start
st auto on; st status; grep -qx 'mode -a stream' "$t/mako"
st toggle; st auto off; st status                                                  # manual keeps it on
if grep -q 'mode -r stream' "$t/mako"; then false; fi                              # mako not released while a flag is left
st toggle; if st status; then false; fi; grep -qx 'mode -r stream' "$t/mako"       # both gone: released
grep -qxF -- '-RTMIN+8 -x \.waybar-wrapped|waybar' "$t/pkill"                       # nixpkgs Waybar's comm is .waybar-wrapped; a loose match would hit waybar-privacy
st auto on; st toggle; st auto off; st status; st toggle; if st status; then false; fi  # auto + manual: either alone keeps it on
fresh; st auto on; st toggle; [[ $(grep -cx stream "$t/modes") == 1 ]]               # both flags on: one stream entry, not two
st toggle; st auto off; if grep -qx stream "$t/modes"; then false; fi              # share on, manual on, manual off, share off: mako left stream mode
fresh
chk '.text == "bandit"' <<<"$(st text bandit)"
chk '.text == "a\"b\\c"' <<<"$(st text 'a"b\c')"                                   # JSON-escaped
st toggle; chk '.text == "•••"' <<<"$(st text bandit)"
fresh; MAKO=fail st toggle; st status; grep -q -- '-RTMIN+8' "$t/pkill"            # makoctl fails: still exit 0, signal still sent
fresh; rc=0; st bogus 2>/dev/null || rc=$?; [[ $rc == 2 ]]
if nr status; then false; fi                                                       # no XDG_RUNTIME_DIR: off, text unmasked, changes are a no-op note
chk '.text == "bandit"' <<<"$(nr text bandit)"
nr toggle 2>"$t/err"; grep -q XDG_RUNTIME_DIR "$t/err"; nr auto on 2>/dev/null
[[ ! -s $t/mako && ! -s $t/pkill ]]

# --- waybar-dns: shield only while tailscale0 has IPv4; probe 0.0.0.0 = blocked
chk '.text == ""' <<<"$(TS=none dns)"                                                # not on the tailnet: no shield
chk '.class == "ok" and (.tooltip | test("Werbeblocker aktiv"))' <<<"$(TS=up GETENT=block dns)"
chk '.class == "off" and (.tooltip | test("Werbung kommt durch"))' <<<"$(TS=up GETENT=real dns)"
s=$SECONDS; chk '.class == "off"' <<<"$(TS=up GETENT=hang dns)"; (( SECONDS - s <= 4 ))  # timeout 3 s, never hangs the bar

echo ok
