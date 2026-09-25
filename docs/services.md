# Services

This is a compact, evidence-scoped map of the two hosts. It records what was
declared in the repository and what Scout observed live; it is not a deployment
or readiness claim.

## Status vocabulary

- **declared** — present in the repository configuration; not necessarily active.
- **observed** — confirmed in the live read-only check.
- **inactive** — intentionally parked or not active in the observed state.
- **unknown** — not confirmed; do not infer it from source or a related service.

## Hosts

| Host | Declared role | Live status |
| --- | --- | --- |
| `bandit` | Framework 13 workstation ([host declaration](../hosts/bandit/default.nix)) | **observed snapshot 2026-09-25** — `bandit-health` passed; no failed units; rootless Docker active; 14 GiB RAM and 51% disk use at the snapshot. This is not continuous health monitoring. |
| `bandit-lab` | NixOS lab/server ([host declaration](../hosts/bandit-lab/default.nix)) | **observed** — NixOS 26.11, 22 active Docker containers, health passed, no failed units, low load, and 4% disk use. |

## Service inventory

| Service(s) | Purpose | Owner / runtime | Access / dependencies | State, data, health |
| --- | --- | --- | --- | --- |
| Docker | Container runtime | NixOS systemd and Docker | Host runtime for the container services | **observed**; 22 active containers |
| Traefik, read-only proxy | HTTP routing and service exposure | Docker, configured by the lab host | Front door for most web apps; Cloudflare Tunnel depends on it | **observed**; exact full listener set unknown |
| Cloudflare Tunnel | External HTTP ingress | NixOS systemd ([WAN config](../hosts/bandit-lab/wan.nix)) | Routes through Traefik; no made-up public domains are recorded here | **observed**; application authentication not verified |
| Tailscale | Private overlay access | NixOS systemd | Wazuh agent traffic and administrative access | **observed**; exact full listeners unknown |
| OpenSSH | Administration and tunnels | NixOS systemd | SSH on port 22; Wazuh dashboard is reached through an SSH tunnel | **observed**; dashboard authentication not verified |
| Samba, Winbind, WSDD | LAN file sharing and discovery | NixOS services | Ports 139 and 445; all-interface exposure needs intentionality | **observed**; share access not verified |
| PostgreSQL | Database service | NixOS systemd | Used by dependent applications; daily backup timer exists | **observed**; backup completed 2026-09-24; restore validity not verified |
| CrowdSec and firewall bouncer | Detection and blocking | NixOS systemd | Reads service activity and applies firewall decisions | **observed**; scheduled updates exist |
| Prometheus, Grafana, cAdvisor, node-exporter, blackbox-exporter | Metrics, dashboards, host/container/exporter probes | Docker; existing monitoring stack ([monitoring files](../hosts/bandit-lab/services/monitoring)) | Grafana consumes Prometheus; no new dashboard is proposed | **observed**; monitoring is existing; alert correctness not fully verified |
| Wazuh manager, indexer, dashboard, agent | SIEM/XDR, indexing, dashboard, agent coverage | Docker via the Wazuh Nix module ([Wazuh module](../hosts/bandit-lab/services/wazuh/default.nix)) | Agent traffic on Tailscale UDP 514 and TCP 1514–1515; dashboard loopback via SSH tunnel | **observed**; authenticated indexer green with 0 unassigned shards, API authentication succeeded, manager core processes healthy, and the lab agent active/current. A sample of 489 recent alerts was mostly levels 7/3 with no high/critical alerts; dashboard browser login and alert delivery remain unverified |
| Portainer server and agent | Docker administration | Docker; agent uses the Docker socket | Agent access is host-root-equivalent; server/agent manage the container runtime | **observed**; ownership and live-connect details need care |
| Vaultwarden | Password manager | Docker | Traefik/Cloudflare path | **observed** as part of the live container set; external login not verified |
| Minecraft | Paper game server | Docker ([Minecraft module](../hosts/bandit-lab/services/minecraft/default.nix)) | Port 25565; all-interface exposure needs intentionality | **observed**; live datapacks were vanilla, `minecraft:improvements`, and `paper`; `trade_rebalance` was absent; restart was healthy; gameplay and restore remain unverified |
| AiiA Ghost, MySQL, Redis | Storefront and its dependencies | Docker | Internal service network and Traefik path | **observed**; external login and application checks not verified |
| SearXNG | Private metasearch | Docker | Loopback/Traefik/Cloudflare path | **observed**; external access not verified |
| WatchYourLAN | LAN device discovery | Docker | LAN-oriented service path | **observed**; discovery completeness not verified |
| Juice Shop, CyberChef, IT Tools | Practice and analyst web tools | Docker | Mostly loopback/Traefik/Cloudflare | **observed**; access controls not verified |
| Mrija Archive | Archive and synchronization service | Docker plus scheduled host sync | Traefik/Cloudflare path; daily sync | **observed**; sync completed 2026-09-24; archive completeness remains unknown; latest image uses a mutable tag |

Persistent data is mainly under `/srv/containers`. Minecraft data and backups
are known there. Scheduled maintenance includes PostgreSQL daily backups,
Mrija daily sync, and Docker, Nix, Btrfs, CrowdSec, and fwupd jobs. An old
stopped workstation Cuttlefish container retains a stored `0.0.0.0:8080`
mapping, but no current listener was observed; its removal is not claimed. The
[health-check module](../hosts/bandit-lab/services/health-check/default.nix)
provides the host health check. The [auto-rebuild module](../hosts/bandit-lab/services/auto-rebuild/default.nix)
owns the lab update path.

## Dependency map

```mermaid
flowchart TD
  host[bandit-lab NixOS]
  host --> systemd[systemd services]
  host --> docker[Docker]
  systemd --> ssh[OpenSSH]
  systemd --> tailscale[Tailscale]
  systemd --> tunnel[Cloudflare Tunnel]
  systemd --> postgres[PostgreSQL]
  systemd --> crowdsec[CrowdSec + firewall bouncer]
  docker --> traefik[Traefik]
  tunnel --> traefik
  traefik --> web[Web services]
  docker --> web
  docker --> monitor[Prometheus + Grafana + exporters]
  monitor --> web
  docker --> wazuh[Wazuh manager + indexer + dashboard + agent]
  tailscale --> wazuh
  ssh --> wazuh
  docker --> portainer[Portainer server + agent]
  portainer --> docker
  docker --> data[/srv/containers]
  postgres --> backups[Daily PostgreSQL backup]
  mrija[Mrija Archive] --> sync[Daily Mrija sync]
```

## Direct listeners and access boundaries

The Scout check confirmed SSH 22, Samba 139/445, Minecraft 25565, and Wazuh
agent traffic on Tailscale UDP 514/TCP 1514–1515. Most web applications are
loopback-, Traefik-, or Cloudflare-mediated. Exact full listener enumeration
was not verified. Portainer Agent's Docker socket is host-root-equivalent;
Minecraft and Samba exposure on all interfaces should remain intentional.

## Source-declared access and security boundaries

- The host firewall is enabled, denies ping, and logs refused connections.
  DNS uses `systemd-resolved` with Cloudflare and Quad9 DNS-over-TLS in
  opportunistic mode, including fallback behavior.
- SMB/WSDD is intentionally LAN-exposed only on `enp44s0` and `wlo1`: TCP
  `139/445/5357` and UDP `137/138/3702` are allowed on those interfaces.
- Minecraft TCP `25565` is explicitly allowed. Wazuh manager traffic binds to
  the Tailscale address on TCP `1514/1515` and UDP `514`; its API, indexer, and
  dashboard remain loopback-published and are reached through SSH tunnels.
- The `wan.nix` route mirror lists public storefront/vault routes:
  `aiia.bandit-lab.mrija.org`, `aiia.at`, `www.aiia.at`,
  `vault.bandit-lab.mrija.org`, and `vault.atmosphaere.at`. Other routes are
  the lab entrypoint or admin/sensitive services:
  `bandit-lab.mrija.org`, `devices.bandit-lab.mrija.org`,
  `devices.atmosphaere.at`, `grafana.bandit-lab.mrija.org`,
  `grafana.atmosphaere.at`, `mail-archive.bandit-lab.mrija.org`,
  `portainer.bandit-lab.mrija.org`, `portainer.atmosphaere.at`,
  `search.bandit-lab.mrija.org`, `search.atmosphaere.at`,
  `ssh-bandit-lab.mrija.org`, `ssh.atmosphaere.at`, `juice.atmosphaere.at`,
  `cyberchef.atmosphaere.at`, and `tools.atmosphaere.at`; the source comments
  require Cloudflare Access for the sensitive routes. The tunnel ingress and
  Access policy are externally managed, so this is not runtime enforcement.
- Docker inter-container communication is disabled by the daemon setting
  (`icc = false`). Traefik uses a restricted, read-only Docker discovery
  proxy; Portainer Agent and the Wazuh agent retain the documented Docker
  socket risk.

## What to check first

1. Run the [lab health check](../hosts/bandit-lab/services/health-check/default.nix)
   and confirm Docker containers plus failed systemd units.
2. Confirm listeners and routes, especially Samba, Minecraft, Wazuh, Traefik,
   Tailscale, and the Cloudflare path.
3. Confirm persistent paths under `/srv/containers`, PostgreSQL backup output,
   and Mrija sync completion.
4. Review Wazuh dashboard browser login and alert delivery, then test the
   external application login paths.
5. Review the 12.3 GB of reclaimable images before removing anything.

## Not yet verified

- Continuous health of `bandit` beyond the 2026-09-25 snapshot.
- PostgreSQL backup restore validity, Minecraft restore/gameplay, and Mrija
  archive completeness.
- Wazuh dashboard browser login and alert delivery. The 489-alert sample is
  not a full security conclusion.
- External login and authorization for the exposed applications.
- The exact complete listener and firewall set.
- DNS attribution remains unresolved: 16,464 Docker resolver errors were
  recorded over seven days, including current intermittent entries, while
  direct Vaultwarden `/alive` returned HTTP 200 and Prometheus reported 10/10
  up. No fix was applied.
- Whether the mutable Mrija latest tag is acceptable.
- Cockpit is inactive; anisette is parked and unimported.
- No new dashboard is needed: monitoring already uses Grafana and Prometheus.

The [Wazuh runbook](runbooks/wazuh.md), [monitoring runbook](runbooks/monitoring.md),
and [Minecraft administration runbook](runbooks/minecraft/ADMIN.md) contain
service-specific verification boundaries.
