# Cloudflare Access for bandit-lab

Cloudflare Tunnel provides transport only. The tunnel is **remotely managed**:
the authoritative per-hostname allowlist lives in the Zero Trust dashboard
(Networks → Tunnels → `bandit-lab` → Public Hostnames, all pointing at
`http://localhost:80`, no wildcard), and the running daemon picks up dashboard
edits within seconds — no rebuild required. `hosts/bandit-lab/wan.nix` carries
a documentation mirror of those routes; keep it in sync when you change the
dashboard. Protect the published hostnames with Cloudflare Zero Trust Access
before relying on them from the Internet — except Vaultwarden, which stays
public by design (see below).

## Configure

1. In Cloudflare Zero Trust, create one **Self-hosted** application for each
   exact hostname:
   - `grafana.bandit-lab.mrija.org`
   - `mail-archive.bandit-lab.mrija.org` — mrija-archive has its own login,
     but the archived email behind it warrants the extra Access gate. (The
     bare `mail.` prefix is reserved for a future real mail server.)
   - `portainer.bandit-lab.mrija.org` — Docker admin UI; never publish it
     without this gate.
   - `search.bandit-lab.mrija.org` — SearXNG has no login of its own, and a
     public metasearch instance is scraped/abused by bots within hours.
   - `changes.bandit-lab.mrija.org` — changedetection.io; the watched-URL
     list itself is sensitive metadata.
   - `devices.bandit-lab.mrija.org` — WatchYourLAN network inventory. It has
     no built-in auth, and the LAN host list (names, MACs, vendors, online
     history) is exactly what an attacker wants for reconnaissance.
   - `ssh-bandit-lab.mrija.org` — required for `ssh bandit-lab-wan`
     (`cloudflared access ssh`). A plain Self-hosted app covering the hostname
     is enough; browser-rendered SSH is optional. Without an Access app the
     connection fails with `websocket: bad handshake`.
2. Add an Allow policy for the intended identity group or email addresses
   (the existing `vino-allow` policy can be reused). Do not add a bypass
   policy for these hostnames.
3. Set an intentional session duration and require the chosen identity
   provider's MFA policy.
4. Keep admin services without an Access app off the WAN entirely. Cockpit's
   socket is loopback-only; reach it through an SSH tunnel:
   `ssh -L 9090:localhost:9090 bandit-lab` → `https://localhost:9090`.
   Portainer is WAN-published behind its Access app, and also remains
   reachable via `ssh -L 9443:localhost:9443 bandit-lab` →
   `https://localhost:9443` as a fallback. Tailscale works too.
5. `vault.bandit-lab.mrija.org` (Vaultwarden) intentionally has **no** Access
   application: native Bitwarden clients cannot complete an interactive
   Access login. It is hardened at the app level instead
   (`SIGNUPS_ALLOWED=false`, `ADMIN_TOKEN` from sops). Do not put an Access
   app in front of it unless all clients are moved to Tailscale first.

## Verify

From an unauthenticated browser session, each hostname should redirect to the
Cloudflare Access login page rather than returning the application. Sign in as
an allowed and a disallowed identity and confirm only the allowed identity can
reach the service.

Test every Vaultwarden client that needs remote access before enforcing Access.
Some native clients cannot complete an interactive Cloudflare Access login; do
not create a broad bypass to work around that limitation. Use a documented,
least-privilege service-authentication approach or keep those clients on
Tailscale instead.

## Avoiding remote lockout on ingress changes

Ingress rules live in the dashboard, not in this repository: the running
`cloudflared` daemon fetches its configuration from Cloudflare and applies
dashboard edits within seconds, so adding or removing a Public Hostname takes
effect immediately without a NixOS rebuild. A hostname with no published
route fails with `websocket: bad handshake`, and an HTTP probe returns 404
from the catch-all rule.

Because changes are instant, the lockout risk is fat-fingering the dashboard
itself: never delete or repoint the route you are currently connected through
(`ssh-bandit-lab.mrija.org` or a Tailscale/Access path) without a second
working way in. After every dashboard edit, mirror it in the `ingress`
attrset in `hosts/bandit-lab/wan.nix` so the repo stays an accurate map of
what is exposed.
