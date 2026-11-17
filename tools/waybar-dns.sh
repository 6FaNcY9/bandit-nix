#!/usr/bin/env bash
# Waybar custom module: DNS shield. Shown only while tailscale0 has an IPv4; the probe name resolving to 0.0.0.0 means the lab's ad-blocking DNS is active.
# Env: BAR_DNS_PROBE (default doubleclick.net). Display only: never changes DNS or Tailscale.
set -uo pipefail

probe=${BAR_DNS_PROBE:-doubleclick.net}

# Not on the tailnet: hidden, no alarm
if ! timeout 2 ip -4 -j addr show dev tailscale0 2>/dev/null | jq -e 'any(.[]?.addr_info[]?; .family == "inet")' >/dev/null 2>&1; then
  echo '{"text":""}'
  exit 0
fi

read -r addr _ < <(timeout 3 getent ahostsv4 "$probe" 2>/dev/null) || true
if [[ $addr == 0.0.0.0 ]]; then
  echo '{"text":"󰒃 DNS","class":"ok","tooltip":"Werbeblocker aktiv (bandit-lab)"}'
else
  echo '{"text":"󰦞 DNS","class":"off","tooltip":"Tailnet verbunden, aber Werbung kommt durch"}'
fi
