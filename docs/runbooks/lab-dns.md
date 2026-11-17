# Tailnet DNS with ad blocking (bandit-lab)

Blocky (`hosts/bandit-lab/services/dns`) answers DNS on `100.125.161.81:53`, tailnet only.
It sends each query to two of Cloudflare, Quad9 and Google (DoH by IP), picked by recent
speed, and takes the first answer; popular names are prefetched before they expire. Ads
and trackers (StevenBlack hosts, OISD big) get `0.0.0.0`. No query log is kept. The lab
itself still uses systemd-resolved.

## Owner console steps (after the deploy)

1. Check from a tailnet device: `dig @100.125.161.81 example.org` gives an address,
   `dig @100.125.161.81 doubleclick.net` gives `0.0.0.0`.
2. Admin console, DNS, Nameservers, Global nameservers: add `100.125.161.81`, then
   `9.9.9.9` as a second one (used only if the lab does not answer), and turn on
   **Override DNS servers**. MagicDNS stays on, so `*.ts.net` names keep working.
3. This applies to every device in the tailnet, guests included.

## Rollback

Turn **Override DNS servers** off and remove `100.125.161.81` in the console: devices go
back to their own DNS within seconds. Removing `./services/dns` from
`hosts/bandit-lab/default.nix` stops Blocky on the next deploy.

## A site is wrongly blocked

Add it under `blocking.allowlists.ads` in `services/dns/default.nix` (a list of
inline domains or URLs, see the Blocky docs) and deploy.

## Laptop (bandit)

The laptop has no global `~.` (`modules/system/tailnet-dns.nix`), so on the tailnet only
Blocky answers. `dns-guard.service` asks Blocky directly every 10 s: after 2 misses it runs
`tailscale set --accept-dns=false` (router + Cloudflare/Quad9 take over, ads come through),
after 2 answers `--accept-dns=true`. Log: `journalctl -u dns-guard`.
Rollback: `sudo systemctl stop dns-guard && sudo tailscale set --accept-dns=true`; for good,
remove `./tailnet-dns.nix` from `modules/system/default.nix`.
