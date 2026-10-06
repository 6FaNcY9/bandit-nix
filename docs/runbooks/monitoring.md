# Monitoring stack (Grafana + Prometheus) on bandit-lab

The canonical reviewed Compose asset is
[`hosts/bandit-lab/services/monitoring/compose.yml`](../../hosts/bandit-lab/services/monitoring/compose.yml),
with project name `monitoring`. It preserves the live node-exporter unit
include, including `ollama`, and publishes no Grafana host port; Grafana is
reached through Traefik/Cloudflare. Until the adoption revision is deployed,
Portainer remains the live owner of the running stack.

Nix exposes the asset at `/etc/bandit-lab/monitoring.compose.yml` and declares
the initially disabled manual lifecycle unit `compose-monitoring`. The unit
only runs Compose `start`/`stop`; it does not create or reconcile containers.

## Portainer environment reassociation

Changing the saved Portainer environment from the local socket to
`portainer-agent:9001` changes Portainer metadata, not Docker or its
containers. Before removing the old environment, record the `monitoring`
stack, containers, project name and persistent bind-mount directories:

```bash
sudo test -d /srv/containers/monitoring/grafana
sudo test -d /srv/containers/monitoring/prometheus
docker ps --filter name=grafana --filter name=prometheus \
  --filter name=blackbox-exporter --filter name=node-exporter \
  --filter name=cadvisor
```

Do not redeploy the stack or delete its containers, networks or data merely to
perform metadata migration. The complete migration and rollback procedure is
in [Portainer Agent](portainer-agent.md).

## Adoption procedure

Review the checked-in Compose asset and the rendered Nix unit first. With
explicit maintenance approval, activate the Nix revision, then compare the
existing Portainer containers with the asset before changing ownership. A
configuration or bind-mount change requires an explicitly approved Compose
recreation; a lifecycle-unit `start` only starts existing containers.

```bash
sudo systemctl status compose-monitoring.service
sudo systemctl start compose-monitoring.service
sudo systemctl stop compose-monitoring.service
sudo docker compose --project-name monitoring \
  --file /etc/bandit-lab/monitoring.compose.yml ps
```

Before an explicit apply, use Compose dry-run and expect the current imported
definition to recreate Grafana, Prometheus, node-exporter and cadvisor. Do not
describe this as a zero-impact takeover:

```bash
sudo docker compose --dry-run --project-name monitoring \
  --file /etc/bandit-lab/monitoring.compose.yml up -d --pull never --no-build
```

The approved apply command is separate from the lifecycle unit:

```bash
sudo docker compose --project-name monitoring \
  --file /etc/bandit-lab/monitoring.compose.yml \
  up -d --pull never --no-build
```

Keep Portainer's current/live ownership wording valid until that approved
handoff is complete. Do not use `down -v`, volume/network prune, or delete
application data.

## Verify

- Before adoption, Portainer shows the existing `monitoring` project and its
  containers; this is live evidence, not source evidence.
- After an approved handoff, `docker compose ... ps` shows Grafana,
  Prometheus, blackbox-exporter, node-exporter and cadvisor running.
- Grafana is reached through `https://grafana.bandit-lab.mrija.org` and the
  existing Cloudflare Access path; no LAN host port `3000` is expected.
- Prometheus targets, direct-origin probes, Grafana authentication and
  persistent bind mounts require separate operator verification.
- Grafana's stored admin password and rotation boundary are documented in
  [secret rotation](secret-rotation.md#grafanas-stored-admin-password).

The monitoring data uses host bind mounts under `/srv/containers/monitoring`.
cadvisor remains privileged with read-only host mounts and must not gain a
Traefik route or published port.

Query Prometheus inside its container because it has no host port:

```bash
docker exec prometheus wget -qO- http://127.0.0.1:9090/api/v1/targets \
  | jq -r '.data.activeTargets[] | [.labels.job, .health, .lastError] | @tsv'
```

Before Portainer retirement, all 10 configured targets should be healthy.
After removing only the Portainer WAN target and recreating Prometheus during
approved maintenance, expect nine; verify the names as well as the count.

Rollback uses the previously reviewed Compose asset and recorded image IDs
with the same project name and bind mounts. A Nix rollback does not revert an
already recreated container definition. Never use `down -v` or prune as a
rollback operation.

## Cockpit "Metrics history": PCP is missing (known, by design)

Cockpit's Metrics page shows live data from the host, but its *history* graphs
need Performance Co-Pilot (PCP): Cockpit's channel imports the Python bindings
`pcp.pmapi` and fails with "python3-pcp not installed" (Cockpit 366,
`cockpit/channels/pcp.py`), and `pmlogger` has to be writing archives. nixpkgs
does not package Performance Co-Pilot (the old `pcp` attribute was removed, and
a search for the suite finds nothing under any other name), so there is nothing
to enable. Making it work would mean maintaining a custom package of the whole
PCP suite plus the `pmcd`/`pmlogger` services and patching Cockpit's Python
environment to see the bindings. That was judged not worth it: this lab already
keeps history in **Prometheus/Grafana** (host, containers, systemd units, probes,
alerts) and **Beszel** (host resource history), and Cockpit stays the tool for
live state, logs and service control (`portainer-retirement.md`). Use Grafana for
history; the message in Cockpit is expected.
