# Laptop DNS: only Blocky on the tailnet (design)

Approved by vino 2026-11-17. Reviewed by architect (Fable).

## Why

On the tailnet the laptop sometimes lets ads through and the bar's DNS shield turns red.
systemd-resolved gives the global servers (Cloudflare/Quad9 from
`modules/system/network.nix`, `Domains=~.`) and `tailscale0` (`~.`, 100.100.100.100 →
Blocky 100.125.161.81) the same rank, asks both in parallel, and caches whichever answers
first for about 5 minutes. A `~.` route-only domain outranks plain DefaultRoute links, so
the Wi-Fi router is not in that race. Blocky itself blocks correctly.

## Goals

- On the tailnet, with Blocky reachable, only Blocky answers.
- DNS never stays dead: lab down, off the tailnet, hotel Wi-Fi with a captive portal
  (Tailscale up but not connected).
- Independent of the phone's watcher (it still switches the tailnet nameserver to Quad9
  after 3 minutes; the laptop no longer relies on it).

## Non-goals

- No change to the lab, to `modules/system/network.nix` (also imported by the lab via
  `modules/server/default.nix`), or to the Tailscale admin console.
- No per-query failover like the phone; no local DNS proxy.
- No change to `tools/waybar-dns.sh`: red during fallback is the truth.

## Approaches

- **A (picked): remove global `~.` on the laptop + a probe service.** Small; hotel works
  because the router joins the race in fallback; one gap of up to ~20 s when the lab dies.
- B: local proxy (Blocky first with 1 s timeout, then DoH), like the phone. Per-query
  failover, but more parts, every off-tailnet query pays the timeout, and DoH fails behind
  a captive portal. Rejected by vino.
- Only remove `~.`: hotel and lab outage leave DNS dead. Rejected.
- Rewrite `tailscale0` with `resolvectl`: tailscaled overwrites it on every reconfig.
  NetworkManager dispatcher: sees no event when the lab dies. Rejected.

## Design

1. Laptop only (module imported from `modules/system/default.nix` or
   `hosts/bandit/default.nix`): `services.resolved.settings.Resolve.Domains` forced to
   empty. The global DNS servers stay. With tailnet DNS on, `tailscale0` is the only `~.`
   and wins alone; with it off, global servers and the router race as normal.
2. A root service, a never-exiting loop (`Restart=always`, after/wants `tailscaled`),
   every 10 s:
   - `dig +time=1 +tries=1 @100.125.161.81 p<random>.example.com` (direct, random name so
     Blocky's cache cannot hide a dead upstream; Blocky keeps no query log).
   - OK = `status: NOERROR` or `NXDOMAIN`; anything else (timeout, SERVFAIL) = fail.
   - 2 fails in a row → `tailscale set --accept-dns=false`, `resolvectl flush-caches`.
   - 2 OKs in a row → `tailscale set --accept-dns=true`, `resolvectl flush-caches`.
   - Start state unknown, so the first verdict always applies. State changes only when
     `tailscale set` exits 0 (tailscaled stopped → retry next tick).

## Accepted costs

- Lab dies: one gap of up to ~20 s, then DNS via router + Cloudflare/Quad9 (ads leak).
- During fallback `*.ts.net` names do not resolve (IPs still work).
- After resume from suspend a short fallback (~30 s) is possible.
- A manual `tailscale up --…` during fallback complains about the non-default pref.
- Shutdown during fallback is fail-open: DNS works, ads leak until the first probe after boot.

## Checks

- Targeted laptop toplevel build (no full `nix flake check`, it is OOM-killed).
- `resolvectl status`: Global without `~.`, `tailscale0` is the only `~.`.
- 10× `resolvectl query --cache=no` on an ad domain → blocked every time.
- Simulated lab death (temporary nft drop to 100.125.161.81): fallback within ~21 s, back
  after removal; DNS still resolves meanwhile.
- `tailscale down`: DNS still resolves.
- Reboot while in fallback: accept-dns returns to true.
- `journalctl -u <service>` after one suspend cycle.

## Left to the builder

Module file name and service name, exact loop code, log lines.
