# Services

This is a compact, evidence-scoped map of the two hosts. It records what was
declared in the repository and what Scout observed live; it is not a deployment
or readiness claim.

The [Obsidian infrastructure notes](infrastructure/obsidian/README.md) provide
navigation to the host and Beszel notes without replacing this inventory or its
dependency map.

## Status vocabulary

- **declared** — present in the repository configuration; not necessarily active.
- **observed** — confirmed in the live read-only check.
- **inactive** — intentionally parked or not active in the observed state.
- **unknown** — not confirmed; do not infer it from source or a related service.

## Hosts

| Host | Declared role | Live status |
| --- | --- | --- |
| `bandit` | Framework 13 workstation ([host declaration](../hosts/bandit/default.nix)) | **observed snapshot 2026-09-25** — `bandit-health` passed; no failed units; rootless Docker active; 14 GiB RAM and 51% disk use at the snapshot. This is not continuous health monitoring. |
| `bandit-lab` | NixOS lab/server ([host declaration](../hosts/bandit-lab/default.nix)) | **observed 2026-09-25 04:13 CEST** — NixOS 26.11, 22 active Docker containers, no failed units, load 1.50, 42 GiB available memory, and 4% disk use. |

## Service inventory

| Service(s) | Purpose | Owner / runtime | Access / dependencies | State, data, health |
| --- | --- | --- | --- | --- |
| Docker | Container runtime | NixOS systemd and Docker | Host runtime for the container services | **observed**; 22 active containers |
| Traefik, read-only proxy | HTTP routing and service exposure | Docker, configured by the lab host | Front door for most web apps; Cloudflare Tunnel depends on it | **observed**; exact full listener set unknown |
| Cloudflare Tunnel | External HTTP ingress | NixOS systemd ([WAN config](../hosts/bandit-lab/wan.nix)) | Routes through Traefik; no made-up public domains are recorded here | **observed**; application authentication not verified |
| Tailscale | Private overlay access | NixOS systemd | Administrative access | **observed**; exact full listeners unknown |
| OpenSSH | Administration and tunnels | NixOS systemd | SSH on port 22 | **observed**; dashboard authentication not verified |
| Samba | File sharing over the tailnet only | NixOS services | TCP 139/445 on `tailscale0` only (decision D5) | **observed**; share access not verified |
| PostgreSQL | Database service | NixOS systemd | Used by dependent applications; daily backup timer exists | **observed**; backup completed 2026-09-24; restore validity not verified |
| CrowdSec and firewall bouncer | Detection and blocking | NixOS systemd | Reads service activity and applies firewall decisions | **observed**; scheduled updates exist |
| Prometheus, Grafana, cAdvisor, node-exporter, blackbox-exporter | Metrics, dashboards, host/container/exporter probes | Docker; reviewed Git Compose asset ([monitoring runbook](runbooks/monitoring.md)); Portainer retired, containers keep running and are managed with host Compose | Grafana consumes Prometheus; no new dashboard is proposed | **observed**; monitoring is existing; alert correctness not fully verified |
| Beszel | Lightweight host resource history | Native NixOS hub and agent ([Beszel module](../hosts/bandit-lab/services/beszel/default.nix)) | Loopback-only hub `127.0.0.1:8090`; access through SSH forwarding; no Docker socket | **observed 2026-09-25**; host metrics, history, restart recovery, and in-app alert verified; container metrics intentionally disabled |
| Vaultwarden | Password manager | Docker | Traefik/Cloudflare path | **observed** as part of the live container set; external login not verified |
| Minecraft | Paper game server | Docker ([Minecraft module](../hosts/bandit-lab/services/minecraft/default.nix)); browser panel and map prepared, not deployed ([panel runbook](runbooks/minecraft/PANEL.md), [migration](runbooks/minecraft/MIGRATION.md)) | Port 25565 on the tailnet address; panel/map on loopback behind Tailscale Serve once deployed | **observed**; live datapacks were vanilla, `minecraft:improvements`, and `paper`; `trade_rebalance` was absent; restart was healthy; an isolated archive extraction restore drill passed; gameplay restore remains unverified |
| AiiA Ghost, MySQL, Redis | Storefront and its dependencies | Docker | Internal service network and Traefik path | **observed**; external login and application checks not verified |
| Mrija Archive | Archive and synchronization service | Docker plus scheduled host sync; reviewed Git Compose asset ([runbook](runbooks/mrija-archive.md)); Portainer retired, containers keep running and are managed with host Compose | Traefik/Cloudflare path; daily sync | **observed**; historical sync runs included timeouts and HTTP 401s, but the 2026-09-25 sync completed with 29,802 emails; archive completeness remains unknown; latest image uses a mutable tag |

Persistent data is mainly under `/srv/containers`. Minecraft data and backups
are known there. Scheduled maintenance includes PostgreSQL daily backups,
Mrija daily sync, and Docker, Nix, Btrfs, CrowdSec, and fwupd jobs. An old
stopped workstation Cuttlefish container retains a stored `0.0.0.0:8080`
mapping, but no current listener was observed; its removal is not claimed. The
[health-check module](../hosts/bandit-lab/services/health-check/default.nix)
provides the host health check. The [auto-rebuild module](../hosts/bandit-lab/services/auto-rebuild/default.nix)
owns the lab update path.

## Dependency map

> 2026-10-08: Wazuh, Portainer, SearXNG, WatchYourLAN, Juice Shop, CyberChef and IT-Tools were retired (unused) and are no longer deployed. Audit evidence below that mentions them is historical.

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

## Latest read-only audit evidence

The 2026-09-25 audit observed `iptables-save v1.8.13 (nf_tables)` active;
the `nft` CLI is absent. The default firewall drops unsolicited input, with
explicit listeners and rules documented above; the complete live firewall set
remains unknown. All running containers had `privileged=false` except cAdvisor,
which had `privileged=true`. Portainer Agent and Wazuh Agent mount the Docker
socket. Minecraft and Wazuh exposure matched the current firewall rules.

## Backup integrity evidence

- Four Minecraft `.tar.gz` archives were gzip- and tar-readable; the recovery
  archive matched its sidecar SHA256. The newest archive was extracted into a
  temporary directory and contained `level.dat` plus the world datapacks
  directory; the temporary copy was removed afterward.
- PostgreSQL `all.sql.gz` and `all.prev.sql.gz` passed gzip integrity checks.
- A manual Btrfs scrub completed on 2026-09-25: 90.96 GiB scanned with no
  errors. The next scheduled scrub is 2026-10-01.

## Source-declared access and security boundaries

- The host firewall is enabled, denies ping, and logs refused connections.
  DNS uses `systemd-resolved` with Cloudflare and Quad9 DNS-over-TLS in
  opportunistic mode, including fallback behavior.
- The host firewall opens ports on `tailscale0` only: SSH (22) and SMB
  (139/445). Nothing is open on the Wi-Fi/LAN interfaces. NetBIOS (nmbd) and
  WS-Discovery are off; mount the share by tailnet address. LLMNR and mDNS are
  off. `ci/lab-surface.nix` enforces this.
- Minecraft TCP `25565` is published on the Tailscale address only. Docker
  published ports bypass the host firewall, so the bind address is the control;
  every published port must bind `127.0.0.1` or the tailnet address. Wazuh manager traffic binds to
  the Tailscale address on TCP `1514/1515` and UDP `514`; its API, indexer, and
  dashboard remain loopback-published and are reached through SSH tunnels.
- The `wan.nix` route mirror lists public storefront/vault routes:
  `aiia.bandit-lab.mrija.org`, `aiia.at`, `www.aiia.at`,
  and `vault.atmosphaere.at`. Other routes are
  the lab entrypoint or admin/sensitive services:
  `bandit-lab.mrija.org`, `devices.bandit-lab.mrija.org`,
  `devices.atmosphaere.at`, `grafana.bandit-lab.mrija.org`,
  `grafana.atmosphaere.at`, `mail-archive.bandit-lab.mrija.org`,
  `portainer.bandit-lab.mrija.org`, `portainer.atmosphaere.at`,
  `search.bandit-lab.mrija.org`, `search.atmosphaere.at`,
  `juice.atmosphaere.at`,
  `cyberchef.atmosphaere.at`, and `tools.atmosphaere.at`; the source comments
  require Cloudflare Access for the sensitive routes. A read-only Cloudflare
  API audit on 2026-09-25 confirmed the configured Access applications and
  allow policies, but tunnel routing and interactive browser/client
  enforcement still need endpoint testing.
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
  archive completeness, and Btrfs scrub result.
- Wazuh dashboard browser login and alert delivery. The 489-alert sample is
  not a full security conclusion.
- External login and authorization for the exposed applications.
- The exact complete listener and firewall set.
- DNS attribution remains unresolved: 16,464 Docker resolver errors were
  recorded over seven days, including current intermittent entries, while
  direct Vaultwarden `/alive` returned HTTP 200 and Prometheus reported 10/10
  up. No fix was applied.
- Whether the mutable Mrija latest tag is acceptable; that container is
  Portainer-managed rather than declared in this repository.
- Wazuh Agent and Portainer Agent retain Docker-socket mounts. This is an
  intentional but host-root-equivalent risk; no socket-proxy migration is
  justified until the required Wazuh Docker-listener API is confirmed.
- Current resource sample: Minecraft used 8.8 GiB of its 12 GiB cap; Wazuh
  Indexer used 5.3 GiB with a 4 GiB Java heap; host memory and CPU headroom
  remained ample. No new global container scheduler is justified by this
  sample.
- Cockpit is inactive; anisette is parked and unimported.
- No new dashboard is needed: monitoring already uses Grafana and Prometheus.

The [Wazuh runbook](runbooks/wazuh.md), [monitoring runbook](runbooks/monitoring.md),
and [Minecraft administration runbook](runbooks/minecraft/ADMIN.md) contain
service-specific verification boundaries.
