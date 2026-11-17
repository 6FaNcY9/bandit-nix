#!/usr/bin/env bash
# Waybar custom module: VPN IP (first IPv4 of a tun* device) -> pt target, as Waybar JSON; `copy target|vpn` puts one on the clipboard.
# Env: BAR_PENTEST_SESSION (pt session file), BAR_GREEN / BAR_RED (pango colours). Stream mode masks the IPs with •••.
set -euo pipefail

session=${BAR_PENTEST_SESSION:-$HOME/src/sec/.pentest-session}
green=${BAR_GREEN:-#61bb46}
red=${BAR_RED:-#ed4749}

vpn=$(timeout 2 ip -4 -j addr 2>/dev/null | jq -r '[.[] | select((.ifname // "") | startswith("tun")) | (.addr_info[]? | .local)][0] // empty' 2>/dev/null || true)
# pt writes CRLF-tolerant key=value lines; the last target= wins
target=$(sed -n 's/^target=//p' "$session" 2>/dev/null | tail -n1 | tr -d '\r ' || true)
mask=0; if waybar-stream status >/dev/null 2>&1; then mask=1; fi

if [[ ${1:-} == copy ]]; then
  case ${2:-} in
    target) val=$target label="Target" ;;
    vpn) val=$vpn label="VPN IP" ;;
    *) echo "usage: waybar-target [copy target|vpn]" >&2; exit 2 ;;
  esac
  if [[ -z $val ]]; then notify-send -t 2000 "$label" "no address"; exit 1; fi
  printf '%s' "$val" | wl-copy
  # the clipboard gets the real value, the notification must not show it on stream
  notify-send -t 2000 "$label copied" "$([[ $mask == 1 ]] && echo '•••' || echo "$val")"
  exit 0
fi

jq -cn --arg vpn "$vpn" --arg target "$target" --arg mask "$mask" --arg g "$green" --arg r "$red" '
  def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
  def shown: if $mask == "1" then "•••" else esc end;
  [if $vpn != "" then {t: "<span color=\"\($g)\">󰖂 \($vpn | shown)</span>", tip: "VPN \($vpn | shown)"} else empty end,
   if $target != "" then {t: "<span color=\"\($r)\">󰓾 \($target | shown)</span>", tip: "Ziel \($target | shown)"} else empty end]
  | {text: (map(.t) | join(" → ")), tooltip: (map(.tip) | join("\n"))}'
