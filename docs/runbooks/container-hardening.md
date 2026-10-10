# Container hardening report (bandit-lab)

Measured on the live lab on 2026-10-06 with `docker inspect` (read-only). This
is a report, not a change: each flag below can break an image in ways only a test
deployment shows, so nothing was switched on blindly. Order the work from the
"first candidates" list and deploy one container at a time.

> **Update 2026-10-10:** Wazuh, WatchYourLAN, SearXNG, Portainer and the toolbox (CyberChef,
> IT-Tools, Juice Shop) were retired in
> `fc3669f` (2026-10-08); their rows below are historical. No container mounts
> `docker.sock` now; Traefik reads Docker through the filtering proxy in
> `hosts/bandit-lab/services/traefik/default.nix`.

Facts: no container sets `no-new-privileges` or a read-only root filesystem.
Capability drops: WatchYourLAN drops ALL (and adds NET_RAW); Grafana drops a
subset. One container is privileged (cAdvisor, needs host access for cgroup
metrics). Only two containers hold the Docker socket: the Wazuh agent (accepted
risk, enforced by `ci/lab-surface.nix`) and Portainer's Agent, which is being
retired (`portainer-retirement.md`). Every published port is bound to loopback or
the tailnet address (`ci/lab-surface.nix`).

| Container | Image user | Privileged | cap-drop | no-new-privileges | Read-only rootfs | Assessment |
| --- | --- | --- | --- | --- | --- | --- |
| vaultwarden | root (drops itself) | no | none | no | no | First candidate: `no-new-privileges`. Writes only `/data` (and `/tmp`): read-only rootfs with a tmpfs `/tmp` is realistic. Highest value (password vault). Changes under `services/vaultwarden/` need the supervised-maintenance path in `bandit-lab-updates.md`. |
| searxng | root | no | none | no | no | Candidate for `no-new-privileges` and cap-drop; writes its settings/cache, test before read-only. |
| cyberchef, it-tools | 101 / root (nginx) | no | none | no | no | nginx images: `no-new-privileges` is safe; cap-drop ALL then add back CHOWN, SETGID, SETUID, NET_BIND_SERVICE; read-only rootfs needs tmpfs for `/var/cache/nginx` and `/var/run`. |
| juice-shop | 65532 | no | none | no | no | Deliberately vulnerable training target: `no-new-privileges` and cap-drop ALL are safe and worthwhile; it writes at runtime, so no read-only rootfs. |
| aiia-ghost | ghost | no | none | no | no | `no-new-privileges` and cap-drop ALL are likely fine (already non-root); Ghost writes content to mounted volumes only. |
| aiia-mysql | root (drops to mysql) | no | none | no | no | `no-new-privileges` is safe (dropping privileges still works); cap-drop ALL then add CHOWN, SETGID, SETUID, DAC_OVERRIDE, FOWNER. Data volume only for writes. |
| aiia-redis | root (drops itself) | no | none | no | no | `no-new-privileges` and cap-drop ALL (add SETGID, SETUID, CHOWN); read-only rootfs feasible. |
| prometheus, node-exporter, blackbox-exporter | nobody / root | no | none | no | no | Already unprivileged: `no-new-privileges`, cap-drop ALL and read-only rootfs (tmpfs where needed) are all expected to work. node-exporter additionally mounts the host root read-only and the D-Bus socket (by design). |
| grafana | 472 | no | partial | no | no | Drops a subset of capabilities already; add `no-new-privileges`. |
| cadvisor | root | **yes** | none | label=disable | no | Needs privileged access to read cgroups/devices; keep, document, and consider replacing by node-exporter's cgroup data if the dashboards allow. |
| deploy-mrija-archive-1 | root | no | none | no | no | Local build (`mrija-archive:latest`, not pinned); mounts the TheHost SSH key read-only and the mail data. `no-new-privileges` and cap-drop ALL are good first steps once the image is known. |
| minecraft | root (entrypoint drops) | no | none | no | no | Memory capped at 12 GiB, 4 CPUs. `no-new-privileges` is safe; cap-drop needs a test with plugins. Writes the whole data volume: no read-only rootfs. |
| watchyourlan | root | no | **ALL** (+ NET_RAW) | no | no | The reference for what is achievable; add `no-new-privileges`. |
| wazuh.manager, wazuh.indexer, wazuh.dashboard | root / wazuh users | no | none | no | no | Large init scripts and a security plugin: test on a copy first. Pinned by digest since 2026-10-06. |
| wazuh.agent | root | no | none | no | no | Holds the Docker socket for container monitoring (accepted risk; allowlisted in `ci/lab-surface.nix`). |
| portainer, portainer-agent | root | no | none | no | no | Being retired; the Agent holds `docker.sock`. |

## Step 1: source changes prepared on 2026-10-10

These rows record declarative flags, not deployed state. Each container is a
separate commit, guarded by `lab-surface`. The owner gives GO for each shipment;
Codex neither pushes nor activates. Vaultwarden goes last and needs the
supervised-maintenance procedure in `bandit-lab-updates.md`.

| Container | Adopted flag | Owner's post-deploy health probe |
| --- | --- | --- |
| aiia-ghost | `no-new-privileges` | HTTP `http://127.0.0.1:2368/` inside its network namespace; expect a successful storefront response (follow redirects), then check `https://aiia.at/` through the normal route. |
| aiia-redis | `no-new-privileges` | `sudo docker exec aiia-redis redis-cli ping` must return `PONG`; check Ghost still serves requests. |
| grafana | `no-new-privileges` | HTTP `http://127.0.0.1:3000/api/health` inside its network namespace; require HTTP 200 and `database: ok`, then load a dashboard through its normal route. |
| blackbox-exporter | `no-new-privileges` | HTTP `http://127.0.0.1:9115/metrics` inside its network namespace, then `/probe?module=http_origin&target=http://grafana:3000/api/health`; require `probe_success 1`. |
| node-exporter | `no-new-privileges` | HTTP `http://127.0.0.1:9100/metrics` inside its network namespace; require `node_scrape_collector_success{collector="systemd"} 1` and `node_filesystem_size_bytes` series. |

For an HTTP probe from the host, use the container's network namespace so no
port needs publishing (owner only; substitute the row's container and URL):

```bash
sudo nsenter -t "$(sudo docker inspect -f '{{.State.Pid}}' aiia-ghost)" -n \
  curl -fsSL --max-time 15 http://127.0.0.1:2368/ >/dev/null
sudo docker inspect -f '{{json .HostConfig.SecurityOpt}}' aiia-ghost
sudo docker logs --since 5m --tail 50 aiia-ghost
```

Confirm the inspect output contains `no-new-privileges`, the probe succeeds,
and logs have no new startup/permission failures. Builds alone cannot establish
image compatibility. If a probe fails, revert that container's flag through the
same deployment procedure; do not alter or restore its application data.

Compose's monitoring unit uses `start`, not `up`, and has
`restartIfChanged = false`. After the owner applies a monitoring flag, recreate
only that service to apply it:

```bash
sudo docker compose -p monitoring -f /etc/bandit-lab/monitoring.compose.yml \
  up -d --no-deps --pull never --no-build --force-recreate SERVICE
```

No runtime checks have been performed for these prepared changes.

## Historical candidate list (2026-10-06)

1. `--security-opt=no-new-privileges` for vaultwarden, searxng, cyberchef,
   it-tools, juice-shop, aiia-ghost, aiia-redis, grafana and the two Prometheus
   exporters. It blocks privilege gain through setuid binaries and does not
   interfere with images that drop privileges at start-up.
2. `--cap-drop=ALL` plus the minimal set for the nginx images and juice-shop.
3. A read-only root filesystem with tmpfs mounts for vaultwarden, cyberchef,
   it-tools and the exporters.

When a flag is adopted for a container, extend `ci/lab-surface.nix` with an
assertion for it (the Docker-socket allowlist there is the pattern), so it cannot
silently disappear. Test each on the lab with `docker logs` and the service's own
probe before moving to the next.
