# bandit-lab runtime audit — 2026-09-21

Read-only SSH audit from bandit. No remote updates, restarts, firewall changes,
or administrator grants were performed. A running container is not proof that
all of its application workflows work.

## Findings requiring follow-up

| Area | Observed evidence | Follow-up |
| --- | --- | --- |
| Minecraft updates | Healthy Paper 26.2 build 124; official latest endpoint reports stable build 126, published September 20. ViaVersion/ViaBackwards 5.11.0 loaded. | Schedule a backed-up server update; this audit did not restart it. |
| Minecraft administration | `ops.json` is empty; RCON disabled; online mode enabled; whitelist disabled. | User subsequently selected `fancy8869`. Configured `OPS=fancy8869` and a local console pipe; pending deployment/container recreation. No live operator grant has been applied. |
| CrowdSec hub updater | The September 22 scheduled run completed successfully; CrowdSec and its firewall bouncer are active. | Resolved; keep the timer and health-check coverage. |
| Archive sync | Historical runs failed with curl status 28 after about 30 seconds on September 19–21. | Resolved and verified on September 22: POST → SSE → rsync → reindex completed with 29,750 emails and exit 0. |
| NVIDIA | Post-maintenance `nvidia-persistenced` is active and `nvidia-smi` reports driver `595.99.02`. | Resolved; retain the harmless legacy `/var/run` PID-path warning unless it becomes operationally noisy. |
| Monitoring coverage | Live Prometheus reports both configured direct-origin probes and four WAN probes healthy. | Keep the origin probes independent from WAN/Access checks; recheck after future monitoring-container changes. |

Paper source: [official latest-build API](https://fill.papermc.io/v3/projects/paper/versions/26.2/builds/latest).
“Latest” is time-sensitive; recheck before updating.

## Containers and management

All 21 containers were running, with zero reported restart counts and no
reported OOM kills at inspection time. These counters cover their current
container lifetimes, not all historical failures.

- Minecraft, Vaultwarden and cAdvisor reported healthy Docker health status.
- Portainer 2.39.6 responded; unauthenticated `/api/endpoints` returned 401.
  Its published management port is loopback-only. The server has no Docker
  socket mount; the agent holds the socket on the private `portainer-control`
  network. Authenticated endpoint administration was not exercised.
- Grafana 13.0.2 reported database health OK. Prometheus, node-exporter,
  cAdvisor and blackbox-exporter targets were UP. Alert notification delivery
  and authenticated Grafana administration were not tested.
- Wazuh 4.14.7 manager daemons were running and the lab agent was Active.
  Dashboard administration and end-to-end detection/notification were not tested.
- Cockpit and WatchYourLAN returned HTTP 200; the archive returned its login
  redirect. Vaultwarden, CyberChef, IT-Tools, SearXNG and Juice Shop origins
  returned HTTP 200; Grafana redirected to login.
- AiiA Ghost was running; its MySQL ping succeeded and Redis answered PONG.
  Storefront, checkout, backups and authenticated application flows were not tested.

Inventory: minecraft, portainer-agent, portainer, aiia-ghost, aiia-redis,
aiia-mysql, wazuh.agent, wazuh.dashboard, wazuh.manager, wazuh.indexer,
juice-shop, vaultwarden, cyberchef, it-tools, searxng, watchyourlan,
deploy-mrija-archive-1, grafana, cadvisor, node-exporter, prometheus,
blackbox-exporter.

## Network and security boundaries

Firewall, Fail2ban, CrowdSec, its firewall bouncer and the correctly named
`cloudflared-tunnel-bandit-lab.service` were active. Current LAN access uses
`wlo1` at 192.168.0.45/24; `enp44s0` was down. SSH also works through the
configured Tailscale alias.

Minecraft publishes TCP 25565 on all IPv4 interfaces. Management listeners
including Portainer, Cockpit, archive, WatchYourLAN and Wazuh web/API ports
were loopback-bound; Wazuh agent ingestion also uses the tailnet address.
Samba listens broadly, with repository firewall openings scoped to `wlo1`
and `enp44s0` and authenticated share access restricted to private/tailnet
source ranges. Binding broadly is not proof of public reachability.

Juice Shop is deliberately vulnerable. Its public hostname redirected to
Cloudflare Access during this audit, while its local origin returned 200.
The complete Access policy, router forwarding rules and alternate ingress
paths were not available for verification.

The Docker agent socket grants powerful host control and cAdvisor is
privileged. Preserve their management boundaries. Docker forwarding rules
need inspection in addition to ordinary host INPUT rules; see
[Docker's firewall documentation](https://docs.docker.com/engine/network/packet-filtering-firewalls/).

`sudo -n` requires a password, so active privileged firewall rules were not
dumped. This audit cannot certify firewall correctness or overall safety.
No vulnerability scan or comprehensive container-version audit was performed.

## Local shell corrections

The lab Starship format used `$custom.net`, leaving `.net` visible instead
of selecting the custom module. It now uses `${custom.net}`. The old command
only calculated traffic counters; it now prints the default-route interface
and its global IPv4 address/prefix, for example `[wlo1 192.168.0.45/24]`.

Ctrl+Delete lacked an explicit Zsh binding on both hosts and a Fish vi insert
binding on bandit. Added the native `kill-word` binding: deletes the next
word, following each shell's word-boundary rules. Ctrl+Backspace is a
separate key. The terminal must transmit the corresponding key sequence.

Validation: full `rtk nix flake check --no-update-lock-file` passed; evaluated
Starship format contains the correct module reference; installed Zsh and
Fish accept and report the bindings. These changes are local and require
configuration activation and new shell sessions before live use. An actual
keyboard interaction through Kitty/SSH/Zellij has not been exercised.
