#!/usr/bin/env bash
# Laptop DNS guard: while Blocky (bandit-lab) answers, keep Tailscale DNS on so only Blocky resolves;
# when it stops answering (lab down, captive portal), turn Tailscale DNS off so router + Cloudflare/Quad9 take over.
# Runs forever as root (dns-guard.service). Design + rollback: docs/runbooks/lab-dns.md.
set -uo pipefail

state="" last="" count=0 # state unknown at start, so the first verdict always applies
while :; do
  # Random name: a cached one would hide a dead upstream behind Blocky's cache.
  out=$(dig +time=1 +tries=1 @100.125.161.81 "p$RANDOM$RANDOM.example.com" 2>&1) || true
  if [[ $out == *"status: NOERROR"* || $out == *"status: NXDOMAIN"* ]]; then verdict=true; else verdict=false; fi
  if [[ $verdict == "$last" ]]; then count=$((count + 1)); else last=$verdict count=1; fi
  # Two equal results in a row before switching; state only moves when tailscale accepted it.
  if ((count >= 2)) && [[ $verdict != "$state" ]] && tailscale set --accept-dns="$verdict"; then
    resolvectl flush-caches || true
    [[ $verdict == true ]] && why="blocky ok" || why="blocky unreachable"
    echo "dns-guard: $why -> accept-dns=$verdict"
    state=$verdict
  fi
  sleep 10
done
