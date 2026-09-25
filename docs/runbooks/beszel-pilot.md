# Beszel host-metrics pilot

This pilot uses the built-in NixOS Beszel hub and agent. Both services bind to
loopback only: the hub at `127.0.0.1:8090` and the agent at
`127.0.0.1:45876`. No firewall rule, proxy route, Docker socket, container
network, or container metrics is enabled. Docker access is also disabled in
the agent environment and its automatically generated Docker group membership
is removed.

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
The Beszel system should show host CPU, memory, disk, network, and available
sensor metrics. Container metrics are intentionally absent.

## Monitoring responsibility split

- Beszel: lightweight host resource history for this pilot
- Portainer: Docker administration, container logs, and container actions
- Wazuh: security monitoring, SIEM events, and security alerts
- NixOS/systemd: declarative service ownership, lifecycle, and hardening
- Git: reviewed configuration and documentation source of truth

## Safe alert test

After authentication and metric collection are verified, create one temporary
low-impact threshold alert in the Beszel UI, trigger it only if the condition
can be reached safely, verify it appears in the intended interface, and delete
or restore the threshold immediately. Record the result and timestamp in the
dated audit record; do not leave a noisy test alert enabled.

## Backup and rollback

During a maintenance window, stop both services and copy the state and the
private credential file to protected backup storage:

```bash
sudo systemctl stop beszel-agent beszel-hub
sudo tar -C / -czf /private/backup/beszel-$(date +%F).tar.gz \
  var/lib/beszel-hub var/lib/beszel-agent etc/beszel/agent.env
sudo systemctl start beszel-hub beszel-agent
```

Restore only with both services stopped, preserving ownership and modes. To
roll back the pilot, remove the Beszel import and module, rebuild the host,
and retain the state directories for a later re-enable; no Docker or proxy
rollback is required.

## Related notes

- [Beszel service note](../infrastructure/obsidian/services/beszel.md)
- [bandit-lab host note](../infrastructure/obsidian/hosts/bandit-lab.md)
- [Service inventory](../services.md)

## Future container metrics boundary

Container metrics require a separately approved design. It would need an
explicit Docker API/socket access decision, supplementary group/capability
review, and corresponding backup and runtime checks. Do not add those through
this pilot.
