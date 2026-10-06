# Cloudflare Access for bandit-lab

Cloudflare Tunnel provides transport only. The tunnel is **remotely managed**:
the authoritative per-hostname allowlist lives in the Zero Trust dashboard
(Networks → Tunnels → `bandit-lab` → Public Hostnames, all pointing at
`http://localhost:80`, no wildcard), and the running daemon picks up dashboard
edits within seconds — no rebuild required. `hosts/bandit-lab/wan.nix` carries
a documentation mirror of those routes; keep it in sync when you change the
dashboard. Protect the published hostnames with Cloudflare Zero Trust Access
before relying on them from the Internet. Vaultwarden client compatibility
must be tested separately before changing its current Access protection.

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
   - `devices.bandit-lab.mrija.org` — WatchYourLAN network inventory. It has
     no built-in auth, and the LAN host list (names, MACs, vendors, online
     history) is exactly what an attacker wants for reconnaissance.
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
5. Vaultwarden is served at the canonical hostname
   `vault.atmosphaere.at`, which is represented by an Access application in
   the live account. The legacy public hostname was retired after client
   migration verification. Keep the app-level hardening
   (`SIGNUPS_ALLOWED=false`, `ADMIN_TOKEN` from sops).

## Verify

The read-only Cloudflare API audit on 2026-09-25 found 11 self-hosted Access
applications (including Vaultwarden) and one WARP application. Each
self-hosted application had the `vino-allow` policy at precedence 1, with a
24-hour session duration. This verifies the configured application/policy
objects only; direct endpoint checks and client testing are still required for
interactive behavior.

From an unauthenticated browser session, each hostname should redirect to the
Cloudflare Access login page rather than returning the application. Sign in as
an allowed and a disallowed identity and confirm only the allowed identity can
reach the service.

Test every Vaultwarden client that needs remote access before enforcing Access.
Some native clients cannot complete an interactive Cloudflare Access login; do
not create a broad bypass to work around that limitation. Use a documented,
least-privilege service-authentication approach or keep those clients on
Tailscale instead.

## Vaultwarden hostname migration (completed)

`vault.atmosphaere.at` is now the sole canonical hostname. The legacy
`vault.bandit-lab.mrija.org` tunnel route was removed after client migration
verification.

For each phone, desktop app, browser extension, and CLI client:

1. Export or record the current server URL and confirm the account can still
   sign in and sync.
2. Change the server URL to `https://vault.atmosphaere.at`.
3. Verify login, unlock, sync, and adding or editing one disposable test item.
4. Remove the test item and repeat on the next client.

Do not reintroduce a second public hostname without repeating the client and
Access verification sequence.

## Avoiding remote lockout on ingress changes

Ingress rules live in the dashboard, not in this repository: the running
`cloudflared` daemon fetches its configuration from Cloudflare and applies
dashboard edits within seconds, so adding or removing a Public Hostname takes
effect immediately without a NixOS rebuild. A hostname with no published
route fails with `websocket: bad handshake`, and an HTTP probe returns 404
from the catch-all rule.

Because changes are instant, the lockout risk is fat-fingering the dashboard
itself: never delete or repoint the route you are currently connected through
without a second working way in. SSH is no longer published through the tunnel
(see below); the admin path is Tailscale, with the machine's own keyboard and
screen as the last resort. After every dashboard edit, mirror it in the `ingress`
attrset in `hosts/bandit-lab/wan.nix` so the repo stays an accurate map of
what is exposed.

## Public SSH was removed (2026-10-06)

**Completed 2026-10-06.** The two live tunnel routes, the Access application
`ssh-bandit-lab` (which covered exactly those two hostnames) and both DNS CNAME
records were deleted; a read-only API check afterwards showed tunnel config
version 23 with 20 hostname routes and no `ssh://` route, tunnel `healthy`, 10
self-hosted Access applications, no DNS records for either name, and the other
sites still redirecting to the Cloudflare Access login. The original objects
are backed up in `~/cloudflare-backup-20261006-081049` on the laptop (tunnel
config, Access app, DNS records) for rollback. The steps below remain the
manual procedure and the record of what was done.

The routes `ssh-bandit-lab.mrija.org` and `ssh.atmosphaere.at` are no longer
declared in `hosts/bandit-lab/wan.nix`, and sshd on the lab listens only on the
Tailscale interface (`docs/SECURITY-PLAN.md`, decision D6). Tailscale is the
only admin path; the local client alias is `bandit-lab` (tailnet address, see
`home/ssh.nix`). The `bandit-lab-wan` alias and the `cloudflared` client were
removed from the laptop.

The dashboard is the source of truth, so the live routes must be removed there
by hand. Do this only after you have confirmed that `ssh bandit-lab` works over
Tailscale from the laptop.

Until the dashboard routes are deleted, public SSH stays reachable: the tunnel
daemon connects to sshd on the loopback interface, which the firewall always
allows, so removing the lines from `wan.nix` (a mirror) does not close it. While
the routes exist they are also the break-glass path if tailnet SSH fails right
after a deployment; the laptop no longer has the `cloudflared` client, so use
`nix run nixpkgs#cloudflared -- access ssh --hostname ssh-bandit-lab.mrija.org`
as an SSH `ProxyCommand`. Delete the routes only once you have confirmed
`ssh bandit-lab` and a second new session work on the new generation.

1. In the Cloudflare Zero Trust dashboard, open your tunnel `bandit-lab`.
   (The repository's older wording was *Networks, Tunnels, bandit-lab, Public
   Hostnames*. Cloudflare's current documentation calls this list **Published
   applications**; the menu path may differ slightly from the old wording, so
   look for the tunnel's list of hostnames.)
2. Delete the two routes `ssh-bandit-lab.mrija.org` and `ssh.atmosphaere.at`.
   Do not touch the other hostnames.
3. In **Access controls, Applications**, delete the Self-hosted application that
   covers those two hostnames, if one exists.
4. Optionally remove the now-unused DNS records for those two hostnames.
5. Verify from a network that is not your tailnet that
   `ssh vino@ssh-bandit-lab.mrija.org` no longer connects, and from the laptop
   that `ssh bandit-lab` still works.

## Hostname inventory (2026-10-06)

Source: `hosts/bandit-lab/wan.nix` (the documentation mirror of the live
tunnel), the Traefik routers in the service modules, and the Access audit above.
"Access status" restates the documented 2026-09-25 audit; the dashboard was not
queried again for this table.

| Hostname | Service | Public? | Access app required? | Status |
| --- | --- | --- | --- | --- |
| `bandit-lab.mrija.org` | Traefik entrypoint | yes | yes (no content of its own) | documented as gated |
| `aiia.at`, `www.aiia.at`, `aiia.bandit-lab.mrija.org` | AiiA shop (Ghost) | yes, storefront | **no**, a storefront cannot sit behind a login; protect `/ghost/` separately | public by design |
| `vault.atmosphaere.at` | Vaultwarden | yes | yes (live Access app; test native clients) | documented as gated |
| `grafana.atmosphaere.at`, `grafana.bandit-lab.mrija.org` | Grafana | yes | yes | documented as gated |
| `mail-archive.bandit-lab.mrija.org` | Mrija mail archive | yes | yes | documented as gated |
| `devices.atmosphaere.at`, `devices.bandit-lab.mrija.org` | WatchYourLAN | yes | **yes, mandatory** (no auth of its own) | documented as gated |
| `search.atmosphaere.at`, `search.bandit-lab.mrija.org` | SearXNG | yes | **yes, mandatory** (bot abuse) | documented as gated |
| `portainer.atmosphaere.at`, `portainer.bandit-lab.mrija.org` | Portainer UI | yes | yes; being retired (D4, `portainer-retirement.md`) | documented as gated |
| `juice.atmosphaere.at`, `cyberchef.atmosphaere.at`, `tools.atmosphaere.at` | Juice Shop, CyberChef, IT-Tools | yes | yes for the training targets (Juice Shop is deliberately vulnerable) | not individually verified |
| `ssh-bandit-lab.mrija.org`, `ssh.atmosphaere.at` | SSH | **removed** | n/a | route, Access app and DNS deleted 2026-10-06 |

Verified 2026-10-06 through the read-only Cloudflare API: every hostname in the
table except the public shop names (`aiia.at`, `www.aiia.at`,
`aiia.bandit-lab.mrija.org`, with `aiia.at/ghost` covered by its own app) and
the bare `bandit-lab.mrija.org` root (Traefik has no router for it) is covered
by an Access application with one `vino-allow` policy and a 24-hour session,
including the three legacy toolbox names (`juice`, `cyberchef`, `tools` under
`bandit-lab.mrija.org`), which share an app with their `atmosphaere.at` name.
