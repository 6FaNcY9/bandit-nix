# Beszel host-metrics pilot

This pilot uses the built-in NixOS Beszel hub and agent. The hub binds to
`127.0.0.1:8090`; the agent connects to it through an outbound WebSocket.
Agent fallback listening is configured for loopback at `127.0.0.1:45876`, but
no persistent agent listener was observed. No firewall rule, proxy route,
Docker socket, container network, or container metrics is enabled. Docker
access is also disabled in the agent environment and its automatically
generated Docker group membership is removed.

## Pre-pilot baseline

Observed on `bandit-lab` at 2026-09-25 06:00 CEST, before Beszel activation:

- Docker containers: 22
- Load average: `0.20, 0.17, 0.20`
- Memory: 62 GiB total, 42 GiB available; swap unused
- `/` and `/srv`: 2.5 TiB total, 94 GiB used (4%)
- Beszel: not installed; no Beszel CPU, memory, or storage usage

Repeat the same host and Docker commands after activation, then record Beszel's
own resource usage and its data-directory size here or in the dated audit
record. Do not compare measurements taken during a Minecraft backup, restart,
or other maintenance window.

Observed after activation on 2026-09-25 at 06:38-06:42 CEST:

- Docker containers: 22; no failed systemd units
- Load average: `0.37, 0.47, 0.35`
- Memory: 62 GiB total, 42 GiB available; swap unused
- `/` and `/srv`: 2.5 TiB total, 94 GiB used (4%)
- Hub: about 17 MiB current memory, 20 MiB peak
- Agent: about 9 MiB current memory, 28 MiB peak
- Persistent state: 912 KiB hub, 4 KiB agent
- CPU, memory, disk, load, network, temperature, uptime, and systemd-service
  metrics populated; container metrics intentionally disabled

Both services survived a simultaneous restart. The agent reconnected by
WebSocket after ten seconds and the hub reused its existing database.

## First bootstrap

The agent credentials are deliberately not in Git. On the first activation,
the hub starts while the agent remains conditionally stopped because
`/etc/beszel/agent.env` does not exist yet. Reach the hub through SSH:

```bash
ssh -N -L 8090:127.0.0.1:8090 bandit-lab
```

Open `http://127.0.0.1:8090`, create the first administrator using the
built-in password authentication, and use **Add System** to generate the
agent credentials. Then create the root-readable private environment file on
`bandit-lab` and put only the generated `KEY=...` and `TOKEN=...` values in
it:

```bash
sudo install -d -m 0750 /etc/beszel
sudo install -m 0600 /dev/null /etc/beszel/agent.env
sudoedit /etc/beszel/agent.env
sudo systemctl restart beszel-agent
```

Do not set password-auth bypass variables. The UI remains loopback-only and
the SSH tunnel is the access boundary.

## Checks and expected scope

```bash
systemctl is-active beszel-hub beszel-agent
systemctl cat beszel-hub beszel-agent
ss -ltn | rg '127\.0\.0\.1:(8090|45876)'
curl http://127.0.0.1:8090/api/health
```

Run the last two commands on `bandit-lab` (or use the SSH tunnel for the hub).
During normal outbound WebSocket operation, only the hub listener is expected.
The Beszel system should show host CPU, memory, disk, network, and available
sensor metrics. Container metrics are intentionally absent.

## Monitoring responsibility split

- Beszel: lightweight host resource history for this pilot
- Prometheus/Grafana: existing authoritative metrics and dashboards
- Portainer: Docker administration, container logs, and container actions
- Wazuh: security monitoring, SIEM events, and security alerts
- NixOS/systemd: declarative service ownership, lifecycle, and hardening
- Git: reviewed configuration and documentation source of truth

## Safe alert test

Verified on 2026-09-25 at 06:56 CEST: a temporary memory-usage alert set to 1%
for one minute was detected and appeared in Beszel's Active Alerts interface.
The threshold was deliberately below the observed 32% usage so no workload or
stress test was needed. The operator then replaced the test threshold with
normal operational alert settings and enabled other selected alerts. Those
manually managed values live in the hub database and should be reviewed in the
UI rather than duplicated in Git.

## Backup and rollback

During a maintenance window, stop both services and copy the state and the
private credential file to protected backup storage:

```bash
sudo systemctl stop beszel-agent beszel-hub
sudo tar -C / -czf /private/backup/beszel-$(date +%F).tar.gz \
  var/lib/private/beszel-hub var/lib/private/beszel-agent \
  etc/beszel/agent.env
sudo systemctl start beszel-hub beszel-agent
```

The public `/var/lib/beszel-*` paths are systemd-managed symlinks, so backup
the real `/var/lib/private/beszel-*` directories shown above. Restore only
with both services stopped, preserving ownership and modes. Store the archive
on root-only backup storage and verify it with `sudo tar -tzf ARCHIVE`.
Restoration has not been tested. Accounts, enrollment, alerts, history, and
`/etc/beszel/agent.env` are manually managed persistent state outside Git.

To roll back the pilot, remove its import from
`hosts/bandit-lab/default.nix`, retain the inactive module, state, and protected
credentials for possible re-enable, then activate the updated configuration.
Verify `beszel-hub` and `beszel-agent` no longer exist and that port 8090 is no
longer listening. No Docker, firewall, or proxy rollback is required.

## Related notes

- [Beszel service note](../infrastructure/obsidian/services/beszel.md)
- [bandit-lab host note](../infrastructure/obsidian/hosts/bandit-lab.md)
- [Service inventory](../services.md)

## Future container metrics boundary

Container metrics require a separately approved design. It would need an
explicit Docker API/socket access decision, supplementary group/capability
review, and corresponding backup and runtime checks. Do not add those through
this pilot.
