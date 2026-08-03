# Cloudflare Access for bandit-lab

Cloudflare Tunnel provides transport only, and the ingress in
`hosts/bandit-lab/wan.nix` is an explicit per-hostname allowlist (no wildcard).
Protect the published hostnames with Cloudflare Zero Trust Access before
relying on them from the Internet — except Vaultwarden, which stays public by
design (see below).

## Configure

1. In Cloudflare Zero Trust, create one **Self-hosted** application for each
   exact hostname:
   - `grafana.bandit-lab.mrija.org`
   - `mail.bandit-lab.mrija.org` — mrija-archive has its own login, but the
     archived email behind it warrants the extra Access gate.
   - `ssh-bandit-lab.mrija.org` — required for `ssh bandit-lab-wan`
     (`cloudflared access ssh`). A plain Self-hosted app covering the hostname
     is enough; browser-rendered SSH is optional. The tunnel ingress rule in
     `hosts/bandit-lab/wan.nix` only forwards traffic that already passed an
     Access application, so without this app the connection fails with
     `websocket: bad handshake`.
2. Add an Allow policy for the intended identity group or email addresses
   (the existing `vino-allow` policy can be reused). Do not add a bypass
   policy for these hostnames.
3. Set an intentional session duration and require the chosen identity
   provider's MFA policy.
4. Keep admin services off the WAN entirely. Portainer has no Traefik labels
   and Cockpit's socket is loopback-only; reach both through SSH tunnels:
   `ssh -L 9443:localhost:9443 bandit-lab` → `https://localhost:9443`
   (Portainer), `ssh -L 9090:localhost:9090 bandit-lab` →
   `https://localhost:9090` (Cockpit). Tailscale works too.
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

The tunnel's running `cloudflared` daemon only serves the ingress rules from
the configuration it was started with. Adding a new ingress rule (such as
`ssh-bandit-lab.mrija.org`) to `hosts/bandit-lab/wan.nix` does nothing until
the server rebuilds and the daemon reconnects. A new hostname with no published
ingress fails with `websocket: bad handshake`, and an HTTP probe returns 404.

Always apply tunnel ingress changes on the server while you still have local
or console access (`sudo lab-update apply`). Never merge an ingress change that
is your only remote access path before it is live on the daemon.
