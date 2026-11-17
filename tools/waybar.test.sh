#!/usr/bin/env bash
# Test for the raw tools/waybar-*.sh scripts with stub commands first on PATH.
# Run: tools/waybar.test.sh
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# Stub commands, each steered per call by an env var: VPN=tun|none, TS=up|none, GETENT=block|real|hang,
# STREAM=on|off (default off), MAKO=ok|fail. makoctl/pkill log their args, wl-copy keeps its stdin.
export BAR_TEST_DIR=$t
mkdir "$t/stub"
stub() { cat >"$t/stub/$1"; chmod +x "$t/stub/$1"; } # stub <name>: stdin is the script
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
exit 0
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
snap 68 "$now";  jq -e '.text == "AI ▰▰▰▰▰▰▰▱▱▱ 68%" and .class == "ok"' <<<"$(ai)"
snap 80 "$now";  jq -e '.class == "warn"' <<<"$(ai)"
snap 95 "$now";  jq -e '.class == "crit"' <<<"$(ai)"
snap 68 "$(date -u -d @$((1794880000 - 601)) +%FT%TZ)"; jq -e '.class == "stale"' <<<"$(ai)"
jq -e '.tooltip | test("Woche 68 % · reset in ") and test("5 h 12 % · reset in ")' <<<"$(ai)"
snap 68 "$now";  jq -e '.tooltip == "Woche 68 % · reset in 3d 6h\n5 h 12 % · reset in 0h 13m"' <<<"$(ai)"  # Xd Yh, Xh Ym
snap 68 "${now%Z}.123Z"; jq -e '.class == "ok"' <<<"$(ai)"                   # JS toISOString has milliseconds
rm "$t/u.json"; jq -e '.text == ""' <<<"$(ai)"
echo '{"seven_day":{"used_percentage":null}}' >"$t/u.json"; jq -e '.text == ""' <<<"$(ai)"
echo garbage >"$t/u.json"; jq -e '.text == ""' <<<"$(ai)"

echo ok
