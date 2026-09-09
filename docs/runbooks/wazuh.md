# Wazuh on bandit-lab

Wazuh is the self-hosted SIEM/XDR: log ingestion, MITRE ATT&CK-mapped
detection rules, file-integrity monitoring, and vulnerability detection, with
agents on every machine you want watched.

The repository now declares the stack in `hosts/bandit-lab/wazuh.nix`,
with sops-managed credentials and persistent Docker volumes. That migration
arrived during this audit; its activation was not verified here. The live
checks below observed the earlier external Compose deployment. See
[the lab handoff](bandit-lab-handoff-2026-09-09.md) for migration details.

## Historical Compose bootstrap

Do not run these bootstrap steps alongside the declarative stack: they would
compete for ports and state. They record the original certificate/setup flow.

> **Status 2026-09-09: DEPLOYED** at `/srv/containers/wazuh` (external compose
> project `wazuh`, console-visible in Portainer). The steps below describe
> initial setup; restoring the current deployment requires its external compose
> files, configuration, certificates and volumes. Actual deviations from the
> original plan: passwords live in a `0600 .env` next to the compose file
> (referenced as `${VAR}`), the indexer admin + kibanaserver bcrypt hashes in
> `config/wazuh_indexer/internal_users.yml` were replaced **before first
> boot**, and indexer `9200` + manager API `55000` are loopback-bound too.

1. On bandit-lab, prepare host directories:

   ```bash
   sudo install -d -m 0750 -o vino -g users /srv/containers/wazuh
   ```

2. Fetch the pinned release and generate certificates (one-time):

   ```bash
   git clone --depth 1 --branch v4.14.7 https://github.com/wazuh/wazuh-docker.git
   cd wazuh-docker/single-node
   sudo docker compose -f generate-indexer-certs.yml run --rm generator
   ```

3. Edit `single-node/docker-compose.yml` before the first `up`:

   - Reference passwords from a `0600 .env` (`${WAZUH_INDEXER_PASSWORD}`,
     `${WAZUH_API_PASSWORD}`, `${WAZUH_DASHBOARD_PASSWORD}`) instead of the
     upstream defaults, and replace the matching bcrypt hashes in
     `config/wazuh_indexer/internal_users.yml` (`admin`, `kibanaserver`) —
     the indexer only reads that file on first boot. The dashboard admin
     password is tracked as the sops secret `wazuh-admin-password`.
   - Set the indexer heap (`OPENSEARCH_JAVA_OPTS`) to `-Xms4g -Xmx4g`; the
     lab has 64 GB, but the indexer does not need more than that for two
     hosts.
   - Do **not** publish dashboard port `443` on a routable interface. Bind it
     to loopback: `"127.0.0.1:443:5601"`. Same for the indexer
     (`"127.0.0.1:9200:9200"`) and the manager API
     (`"127.0.0.1:55000:55000"`). Access the dashboard via SSH/Tailscale port
     forward, same as Cockpit and Portainer:

     ```bash
     ssh -L 8443:127.0.0.1:443 bandit-lab
     # → https://localhost:8443 (accept the self-signed cert)
     ```

   The stack is started with plain `sudo docker compose up -d` in
   `/srv/containers/wazuh` (it shows up in Portainer as an external stack —
   Portainer stays console-only).

4. Verify the running containers and connected agents (container state alone
   does not prove successful ingestion):

   ```bash
   docker ps --filter name=wazuh
   docker exec wazuh-wazuh.manager-1 /var/ossec/bin/agent_control -l
   ```

   Check the dashboard for recent events from both hosts.

## Agents and coverage

Verified on 2026-09-09: manager 4.14.7 reports `bandit` (002) and
`bandit-lab` (003) Active, alongside its local manager identity (000).

- **bandit-lab** was running a separate Docker agent in the external Compose
  project; the new lab module declares that agent too.
  The manager's local identity monitors its container; it does not replace
  the host agent.
- **bandit** uses the Podman agent declared in `nixos/wazuh-agent.nix`.
  Manager TCP ports 1514/1515 are bound to `100.125.161.81` on the tailnet.
  Persisted `/var/lib/wazuh-agent/etc` retains enrollment identity across
  container recreation. Startup installs `ossec.conf` with mode 0640 and
  group 999 so the agent can read it after dropping privileges.
- Host coverage comes from mounted journald data and FIM paths under `/host`.
  Inventory, rootcheck and default SCA policies run in the container's view
  of the system. Package vulnerability results therefore do not establish
  NixOS host package coverage. NixOS `/etc` symlinks into an unmounted Nix
  store also limit file-content coverage.
- The laptop configuration disables the image's Amazon Linux SCA policies.
  Check the separate lab agent configuration in
  `hosts/bandit-lab/wazuh/config/wazuh_agent_ossec.conf` for equivalent policy
  coverage before enabling SCA there. Keep host vulnerability assessment in the existing
  Nix/vulnix workflow; inspect actual closures and advisories before acting.
- Journald filters use separate blocks for OR semantics and restrict ingestion
  to security-relevant sources. NixOS Samba units are `samba-smbd.service`
  and `samba-nmbd.service`, not `smbd.service` and `nmbd.service`; mirror the
  corrected filter in the separate lab agent configuration too.
- Container active response is not host firewall enforcement. CrowdSec and
  its host firewall bouncer provide that separate integration.

After a laptop rebuild, check `systemctl status podman-wazuh-agent` and
confirm fresh host events in the dashboard. For external compose changes,
update the persistent agent configuration as well as any seed file before
restarting the agent; a populated volume can hide changes to the image seed.
Do not delete enrollment state to apply a configuration change.

See the upstream [SCA settings](https://documentation.wazuh.com/current/user-manual/reference/ossec-conf/sca.html)
and [inventory architecture](https://documentation.wazuh.com/current/user-manual/capabilities/system-inventory/how-it-works.html).

## Recovery and remaining operational gaps

Back up persistent agent keys, manager state, certificates and the secrets
recovery material to encrypted off-host storage. Retain the old external
Compose/configuration and `.env` while the migration remains reversible. Decide index retention and
snapshot policy separately. A Git checkout alone cannot restore this stack;
test a restore before treating it as recoverable. File mode 0600 protects the
password file from ordinary users, but Docker administrators can inspect
container environment variables.

Both hosts now declare native `smartd` disk monitoring in `nixos/firmware.nix`.
After activation, check `systemctl status smartd` and `journalctl -u smartd -b`
for detected devices and unsupported hardware. Default notifications use the
journal and local wall messages, with desktop notifications on the laptop;
remote delivery still needs a configured
recipient/channel. The live lab had no active smartd during this audit.

Prioritize encrypted off-host restores and tested remote alert delivery over
another overlapping scanner or dashboard. Wazuh, CrowdSec and the existing
Prometheus/Grafana stack already cover detection, enforcement and metrics.
Network IDS needs a usable traffic feed; phishing infrastructure needs an
explicit training use case and workable mail delivery. Neither is enabled
by this change.

## Notes

- Resource floor: ~4 GB RAM for the indexer + ~2 GB for the rest. Fine on the
  lab; do not co-locate on anything smaller.
- Disk: plan ~50 GB for a few weeks of log retention on 4 TB NVMe.
- The dashboard stays loopback-only deliberately — a SIEM console is the
  highest-value admin target on the network; it never goes through the
  Cloudflare tunnel.
