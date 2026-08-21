# Monitoring stack (Grafana + Prometheus) on bandit-lab

The stack is managed in **Portainer** (Stacks → `monitoring`). Host-side files
and secrets are declared in `hosts/bandit-lab/monitoring.nix`; edit them there
and rebuild bandit-lab, then restart the stack in Portainer.

## Portainer environment reassociation

Changing the saved Portainer environment from the local socket to
`portainer-agent:9001` changes Portainer metadata, not the Docker engine or its
containers. Before removing the old environment, record the `monitoring` stack
and its containers and confirm the persistent bind-mount directories exist:

```bash
sudo test -d /srv/containers/monitoring/grafana
sudo test -d /srv/containers/monitoring/prometheus
docker ps --filter name=grafana --filter name=prometheus \
  --filter name=blackbox-exporter --filter name=node-exporter \
  --filter name=cadvisor
```

After adding the Agent environment, open **Stacks**, select **Show all orphaned
stacks**, and associate `monitoring` with the new environment. Do not redeploy
the stack or delete its containers, networks, or data directories merely to
perform this metadata migration. Verify that the stack page opens, lists the
existing containers, and exposes its normal stack actions. A Portainer summary
showing zero Docker volumes is expected here: the monitoring data uses host
bind mounts under `/srv/containers/monitoring`, not named Docker volumes.

The complete migration and rollback procedure is in
[Portainer Agent](portainer-agent.md).

## Stack definition

Paste into Portainer → Stacks → Add stack (name: `monitoring`):

```yaml
networks:
  proxy:
    external: true
  monitoring:

services:
  grafana:
    image: grafana/grafana-oss:13.0.2
    container_name: grafana
    restart: unless-stopped
    ports:
      # LAN access at http://<bandit-lab-lan-ip>:3000 — matches how the other
      # LAN services are exposed (Docker NAT, no extra firewall rule needed).
      # WAN access goes through Traefik + Cloudflare Tunnel, not this port.
      - "3000:3000"
    networks:
      - proxy
      - monitoring
    environment:
      GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana-admin-password
      GF_USERS_ALLOW_SIGN_UP: "false"
    volumes:
      - /srv/containers/monitoring/grafana:/var/lib/grafana
      - /srv/containers/monitoring/grafana-provisioning:/etc/grafana/provisioning:ro
      - /srv/containers/monitoring/grafana-dashboards:/var/lib/grafana-dashboards:ro
      - /run/secrets/grafana-admin-password:/run/secrets/grafana-admin-password:ro
    labels:
      traefik.enable: "true"
      traefik.http.routers.grafana.rule: Host(`grafana.bandit-lab.mrija.org`)
      traefik.http.routers.grafana.entrypoints: web
      traefik.http.services.grafana.loadbalancer.server.port: "3000"
    depends_on:
      - prometheus

  prometheus:
    image: prom/prometheus:v3.13.2
    container_name: prometheus
    restart: unless-stopped
    networks:
      - monitoring
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.retention.time=30d
    volumes:
      - /srv/containers/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - /srv/containers/monitoring/prometheus:/prometheus

  blackbox-exporter:
    image: prom/blackbox-exporter:v0.28.0
    container_name: blackbox-exporter
    restart: unless-stopped
    networks:
      - monitoring
    command:
      - --config.file=/etc/blackbox_exporter/config.yml
    volumes:
      - /srv/containers/monitoring/blackbox.yml:/etc/blackbox_exporter/config.yml:ro

  node-exporter:
    image: prom/node-exporter:v1.12.1
    container_name: node-exporter
    restart: unless-stopped
    pid: host
    networks:
      - monitoring
    command:
      - --path.rootfs=/host
      # Per-unit up/down for the services bandit-lab-health cares about.
      # Needs the host D-Bus socket (mounted below) to talk to systemd.
      # NOTE: node-exporter hard-codes /var/run/dbus — inside the container
      # /var/run is NOT a symlink to /run like on the NixOS host, so the
      # mount must target /var/run/dbus explicitly.
      - --collector.systemd
      - --collector.systemd.unit-include=(sshd|docker|containerd|traefik|cloudflared.*|postgresql|smbd|nmbd|tailscaled|lab-update-.*)\.service
    volumes:
      - /:/host:ro,rslave
      - /run/dbus:/var/run/dbus:ro

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.55.1
    container_name: cadvisor
    restart: unless-stopped
    privileged: true
    networks:
      - monitoring
    # dockerd uses the containerd snapshotter and spawns its own containerd
    # at /var/run/docker/containerd/containerd.sock (not the cadvisor default
    # /run/containerd/containerd.sock). Without this flag the Docker factory
    # never registers and cadvisor exports only host cgroups — dashboards
    # filtering on name=~".+" stay empty.
    command:
      - --containerd=/var/run/docker/containerd/containerd.sock
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk:/dev/disk:ro
```

## Deploy / update

1. Deploy the current config on bandit-lab (`sudo lab-update apply` or
   `sudo nixos-rebuild switch --flake .#bandit-lab`) — this creates the
   `grafana` host user, `/srv/containers/monitoring/*`, and the sops secret.
2. **Remove the legacy `grafan` stack first** (Portainer → Stacks): it
   publishes host port 3000, which the new stack also needs, and it carries
   a plaintext admin password in its container env. Its named volume
   (`grafan_grafana_data`) can be deleted afterwards if nothing in it is
   worth keeping.
3. Deploy or redeploy the `monitoring` stack in Portainer (paste the YAML
   above).
4. **Upgrading from the pre-dashboards provisioning?** The datasource was
   first provisioned without a `uid` and now pins `uid: prometheus`; Grafana
   cannot re-key the old row and crash-loops with
   `Datasource provisioning error: data source not found`. Clear the stale
   row once (provisioning recreates it; all content is provisioned, nothing
   is lost):

   ```bash
   docker stop grafana
   docker run --rm -v /srv/containers/monitoring/grafana:/db alpine \
     sh -c "apk add --quiet --no-cache sqlite && sqlite3 /db/grafana.db 'DELETE FROM data_source;'"
   docker start grafana
   ```
5. Cloudflare dashboard: confirm DNS covers `grafana.bandit-lab.mrija.org`
   (the `*.bandit-lab.mrija.org` CNAME should) and add a Cloudflare Access
   application per `docs/runbooks/cloudflare-access.md`.

## Verify

- Portainer shows `bandit-lab` as **Up**, with connection type **Agent** and
  URL `portainer-agent:9001`; the `monitoring` stack opens and controls its
  existing containers. The separate **Disconnected** live-connect indicator
  is not the environment health status.
- `docker ps` shows grafana, prometheus, blackbox-exporter, node-exporter,
  cadvisor up.
- LAN: `curl http://192.168.1.2:3000/api/health` returns `200` from any LAN
  machine.
- Prometheus targets — the container publishes no host port, so query its
  API in place instead of port-forwarding:

  ```bash
  ssh bandit-lab "docker exec prometheus wget -qO- http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'"
  ```

  All jobs should report `health: "up"`. The Prometheus UI is intentionally
  not exposed (no Traefik, no published port). If a UI is wanted, forward
  the container IP — obtain it via
  `docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' prometheus` —
  instead of localhost.
- https://grafana.bandit-lab.mrija.org loads behind Cloudflare Access;
  log in as `admin` with the password from
  `sudo cat /run/secrets/grafana-admin-password`; the Prometheus datasource
  is pre-configured and green.
- Dashboards are file-provisioned from `hosts/bandit-lab/monitoring.nix`:
  "Node Exporter Full" (host CPU/RAM/disk/network), "Cadvisor exporter"
  (per-container), and "WAN Probes" (end-to-end HTTPS checks of the four
  tunnel hostnames, incl. TLS expiry). Alert rules (target down, WAN probe
  failing, disk <15% free, memory <10% available) live under
  Alerting → Alert rules in the `bandit-lab` group; they are UI-only until a
  contact point is configured.

## Notes

- Only Grafana joins the `proxy` network; never add Traefik labels to the
  other services.
- cadvisor runs `privileged: true` with read-only host mounts: container
  metrics need broad `/sys` and `docker.sock` access, which makes cadvisor
  host-root-equivalent. This is acceptable only because it is stack-internal —
  never give it Traefik labels or a host port.
- Config changes (scrape config, provisioning) require a bandit-lab rebuild
  **and** a stack restart in Portainer — Nix does not manage these containers.
