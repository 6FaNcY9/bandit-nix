# Portainer retirement on bandit-lab

This is a supervised, reversible retirement plan. It removes Portainer Server
and Agent after their Docker-managed work has an authoritative host procedure.
It does not deploy, stop, delete, or mutate live services by itself.

## Scope and non-goals

- Remove Portainer and its Agent, while retaining `/var/lib/portainer` as
  recoverable evidence/data.
- Move the `monitoring` and Mrija archive stack workflows to reviewed host
  Compose/systemd procedures, preserving their discovered project names,
  volumes, bind mounts, networks, restart policy, and secrets references.
- Replace Portainer with the existing Cockpit plus Beszel, not another Docker
  manager. Keep Prometheus/Grafana for metrics, dashboards and alerts, and
  Wazuh for SIEM. Authenticated SSH plus systemd and Docker CLI remain the
  control path.
- Do not redesign Docker, replace monitoring, migrate application data, or
  delete Cloudflare DNS/Access objects without a separate explicit GO gate.

Portainer is removed because it is an unnecessary privileged control plane,
not because another UI is needed. The Agent mounts `/var/run/docker.sock`;
Docker socket access is effectively host-root access. The Server is reached
through the Agent and its `/var/lib/portainer` state is separate from
application data. Current ownership is split: Nix declares host paths,
secrets, health checks and tunnel mirrors; Portainer owns the live external
Compose definitions and day-to-day stack actions.

## Approved replacement and responsibility split

Cockpit was verified on 2026-09-25 as enabled, active, listening only on
`127.0.0.1:9090`, and returning HTTP 200 through local TLS. It is configured
with `cockpit-files` and the custom theme. Access it through an SSH tunnel over
Tailscale; do not expose Cockpit publicly.

- Nix repository: declarative source, persistent configuration, secrets and
  service definitions.
- systemd/Docker: activation, service lifecycle and container procedures.
- Cockpit: privileged host inspection and the approved host administration
  pilot.
- Beszel: lightweight host resource history.
- Prometheus/Grafana: metrics, dashboards and alerts.
- Wazuh: SIEM and security events.

Before the Portainer GO gate, pilot Cockpit by inspecting failed units, logs
and files, then perform one separately approved restart of a noncritical
Nix-managed service. Assess usability and record the result. Do not perform
package updates, persistent enable/disable changes, or edits to Nix-managed
files in Cockpit. Persistent changes go through Git/Nix. Cockpit is privileged
administration, and membership in the `vino` Docker group is root-equivalent.

Dockge, Arcane and Komodo are rejected for this architecture: they restore
`docker.sock` or competing mutation paths, or add unnecessary orchestration.

## 1. Preflight inventory (read-only)

Run on the authoritative host. Save output with the change record; redact
tokens, passwords, cookies and private keys.

```bash
sudo docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
sudo docker stack ls 2>/dev/null || true
sudo docker network ls
sudo docker volume ls
sudo docker inspect portainer portainer-agent
sudo systemctl list-units --type=service --all | rg -i 'portainer|monitoring|mrija|health|lab-update'
sudo systemctl list-timers --all | rg -i 'health|lab-update'
sudo bandit-lab-health
sudo lab-update check
```

For every `monitoring` and Mrija container, record the Compose project and
service labels, image digests/tags, command, env-file/secret *paths* (not
contents), mounts, networks, published ports, restart policy, and health state:

```bash
sudo docker inspect -f '{{.Name}} project={{index .Config.Labels "com.docker.compose.project"}} service={{index .Config.Labels "com.docker.compose.service"}} image={{.Config.Image}} status={{.State.Status}}' <CONTAINER>
sudo docker inspect -f '{{range .Mounts}}{{println .Source "->" .Destination .RW}}{{end}}' <CONTAINER>
sudo docker inspect -f '{{range $n, $_ := .NetworkSettings.Networks}}{{println $n}}{{end}}' <CONTAINER>
sudo docker inspect <CONTAINER> | jq -r '.[0].Config.Env[]? | split("=")[0]'
```

Record Portainer's visible stack definitions/settings, including project names
and external networks, and the Mrija deployment's image, data/maildir paths,
secret-file references and sync/systemd relationship. Export definitions from
Portainer if available; otherwise save redacted `docker inspect` output and
the UI's stack YAML. Never put secret values in Git.

## 2. Consistent Portainer backup

First identify and approve a destination with the operator; do not guess one:

```bash
findmnt -T /var/lib/portainer
df -h /var/lib/portainer
test -d <VERIFIED-BACKUP-DIRECTORY>
```

During the maintenance window, stop only Portainer's own units, create and
hash the archive, then start them again if the retirement has not proceeded:

```bash
sudo systemctl stop docker-portainer.service docker-portainer-agent.service
sudo tar -C /var/lib -czf <VERIFIED-BACKUP-DIRECTORY>/portainer-$(date +%F).tar.gz portainer
sudo tar -tzf <VERIFIED-BACKUP-DIRECTORY>/portainer-$(date +%F).tar.gz >/dev/null
sudo sha256sum <VERIFIED-BACKUP-DIRECTORY>/portainer-$(date +%F).tar.gz
sudo systemctl start docker-portainer-agent.service docker-portainer.service
```

Do not call the backup verified until the destination, archive listing, hash,
ownership/permissions, and an operator-approved restore test are recorded.
Retain `/var/lib/portainer`; this plan never deletes it.

## 3. Establish host authority before stopping Portainer

For each stack, put a reviewed Compose file and a systemd procedure under the
host's approved administration path (exact path is a deployment decision, not
invented here). Use the recorded project name explicitly:

```bash
sudo docker compose -p <RECORDED_PROJECT> -f <APPROVED_COMPOSE_FILE> config
sudo docker compose -p <RECORDED_PROJECT> -f <APPROVED_COMPOSE_FILE> ps
sudo docker compose -p <RECORDED_PROJECT> -f <APPROVED_COMPOSE_FILE> up -d
sudo docker compose -p <RECORDED_PROJECT> -f <APPROVED_COMPOSE_FILE> ps
```

The systemd unit must order after Docker, reference the approved Compose file,
use the same project name, and provide explicit `start`, `stop`, `restart` and
status/log procedures. Preserve existing named volumes, host bind paths,
external `proxy`/other networks, container names where required, and all
secret references. Do not use `down -v`, `docker volume prune`, network prune,
or any deletion of application volumes/data.

For monitoring, a configuration or bind-mount change requires container
recreation; a restart only restarts the old container definition. Verify
Grafana, Prometheus, blackbox-exporter, node-exporter and cadvisor, Prometheus
targets, direct-origin probes, Grafana authentication and the existing
Cloudflare Access path. For Mrija, recreate only after the reviewed Compose
definition and file-backed secret references are ready; restart is sufficient
only for a restart with no definition, mount, network or secret change.
Verify authenticated login/API, archive data/maildir visibility, sync status,
logs, health endpoint and the relevant systemd sync unit.

With separate maintenance approval, run the new procedure once while Portainer
is still available, compare the container/mount/network/project inventory, and
record the result. A restart must not be described as a recreation or as proof
that new Compose settings were applied.

## 4. Reversible disable phase

Schedule a maintenance window. Coordinate with the health-check policy and the
hourly `lab-update-apply.timer`: pause/disable the updater only through the
approved supervised procedure, record its prior state, and prevent it from
activating an intermediate source revision. Do not bypass signed-update or
health gates. Confirm `bandit-lab-health` is green before and after each
boundary.

Prepare one reviewed Nix revision that removes the Portainer Server, Agent and
private network declarations together with their mandatory health checks and
Portainer blackbox probe. Keep `/var/lib/portainer` and all application data.
Do not use `systemctl disable`: these units are generated by Nix and a later
activation can recreate them.

**GO gate: deploy the Portainer-disable revision only when** the backup is
accepted, both host procedures have passed, monitoring and Mrija verification
is green, rollback access is available, and the operator explicitly approves
the stop. Test and activate that complete revision as one change; do not stop
Portainer first and leave the old health gate active.

## 5. Source and external cleanup

The disable revision changes these source locations:

- `hosts/bandit-lab/services/webhost/default.nix`: Server/Agent containers,
  networks, labels and socket-related assertions.
- `hosts/bandit-lab/services/health-check/default.nix`: Portainer checks and
  dependencies, while retaining application/host health coverage.
- `hosts/bandit-lab/services/monitoring/prometheus.nix`: remove the Portainer
  WAN probe while retaining all other probes.
- Runbooks, service inventory, infrastructure notes, and updater/monitoring
  references that still claim Portainer is authoritative.

After that revision has remained healthy for the agreed observation period,
retire the external route, remove its mirror from `hosts/bandit-lab/wan.nix`,
and archive superseded Portainer procedures.

The Nix `wan.nix` entries are only a mirror. Separately inspect the actual
Cloudflare Tunnel ingress, DNS records, and Cloudflare Access applications and
policies for both `portainer.atmosphaere.at` and
`portainer.bandit-lab.mrija.org`.

**GO gate: delete external Cloudflare routes/DNS/Access objects only when**
the route is confirmed unused, no bookmark/client/monitor depends on it, the
replacement/retirement is documented, and the operator explicitly approves
each deletion. A source cleanup or local route removal is not proof that the
remote object was removed.

## 6. Verification and rollback

```bash
sudo systemctl is-enabled docker-portainer.service docker-portainer-agent.service
sudo systemctl is-active <MONITORING_SYSTEMD_UNIT> <MRIJA_SYSTEMD_UNIT>
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
sudo ss -ltnp | rg ':9443\b' || true
sudo bandit-lab-health
sudo lab-update check
```

After the disable revision, both Portainer units should be absent or disabled,
both containers should be absent, and no listener should remain on port 9443.

Also verify the monitoring and Mrija checks in their runbooks, Cloudflare
Access behavior for retained services, logs after one scheduled interval, and
that the hourly updater remains in its recorded intended state.

If any gate fails, stop cleanup, preserve all data, restore the prior Nix
generation or reviewed source revision, re-enable the updater only when safe,
and start the backed-up Portainer units. Restore `/var/lib/portainer` only if
the Server state itself is missing or corrupt, using the recorded hash and an
approved restore test. Never roll back by removing application volumes or
redeploying containers blindly.
