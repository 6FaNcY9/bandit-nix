# Cloudflare Access for bandit-lab

Cloudflare Tunnel provides transport only. Protect the public Vaultwarden and
Portainer hostnames with Cloudflare Zero Trust Access before relying on them
from the Internet.

## Configure

1. In Cloudflare Zero Trust, create one **Self-hosted** application for each
   exact hostname:
   - `vaultwarden.bandit-lab.mrija.org`
   - `portainer.bandit-lab.mrija.org`
   - `grafana.bandit-lab.mrija.org`
   - `ssh-bandit-lab.mrija.org` — required for `ssh bandit-lab-wan`
     (`cloudflared access ssh`). A plain Self-hosted app covering the hostname
     is enough; browser-rendered SSH is optional. The tunnel ingress rule in
     `hosts/bandit-lab/wan.nix` only forwards traffic that already passed an
     Access application, so without this app the connection fails with
     `websocket: bad handshake`.
2. Add an Allow policy for the intended identity group or email addresses.
   Do not add a bypass policy for these hostnames.
3. Set an intentional session duration and require the chosen identity
   provider's MFA policy.
4. Keep Cockpit, Samba, Ollama, and direct Traefik ports off the WAN. Cockpit
   and Portainer also remain reachable through SSH or Tailscale tunnels.

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
