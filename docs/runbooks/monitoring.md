# Monitoring stack (Grafana + Prometheus) on bandit-lab

The stack is managed in **Portainer** (Stacks → `monitoring`). Host-side files
and secrets are declared in `hosts/bandit-lab/monitoring.nix`; edit them there
and rebuild bandit-lab, then restart the stack in Portainer.

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
    networks:
      - proxy
      - monitoring
    environment:
      GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana-admin-password
      GF_USERS_ALLOW_SIGN_UP: "false"
    volumes:
      - /srv/containers/monitoring/grafana:/var/lib/grafana
      - /srv/containers/monitoring/grafana-provisioning:/etc/grafana/provisioning:ro
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
      - --storage.tsdb.retention.time=15d
    volumes:
      - /srv/containers/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - /srv/containers/monitoring/prometheus:/prometheus

  node-exporter:
    image: prom/node-exporter:v1.12.1
    container_name: node-exporter
    restart: unless-stopped
    pid: host
    networks:
      - monitoring
    command:
      - --path.rootfs=/host
    volumes:
      - /:/host:ro,rslave

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.55.1
    container_name: cadvisor
    restart: unless-stopped
    privileged: true
    networks:
      - monitoring
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk:/dev/disk:ro
```

## Deploy / update

1. `sudo nixos-rebuild switch --flake .#bandit-lab` on bandit-lab (creates
   `/srv/containers/monitoring/*` and the sops secret).
2. Deploy or redeploy the stack in Portainer.
3. Cloudflare dashboard: confirm DNS covers `grafana.bandit-lab.mrija.org`
   (the `*.bandit-lab.mrija.org` CNAME should) and add a Cloudflare Access
   application per `docs/runbooks/cloudflare-access.md`.

## Verify

- `docker ps` shows grafana, prometheus, node-exporter, cadvisor up.
- Prometheus targets: `ssh -L 9090:localhost:9090 bandit-lab`, then
  http://localhost:9090/targets — all jobs `up`. (Prometheus is not exposed
  via Traefik by design.)
- https://grafana.bandit-lab.mrija.org loads behind Cloudflare Access;
  log in as `admin` with the password from
  `sudo cat /run/secrets/grafana-admin-password`; the Prometheus datasource
  is pre-configured and green.

## Notes

- Only Grafana joins the `proxy` network; never add Traefik labels to the
  other services.
- Config changes (scrape config, provisioning) require a bandit-lab rebuild
  **and** a stack restart in Portainer — Nix does not manage these containers.
