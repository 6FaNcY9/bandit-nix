# Wazuh on bandit-lab

Wazuh is the self-hosted SIEM/XDR: log ingestion, MITRE ATT&CK-mapped
detection rules, file-integrity monitoring, and vulnerability detection, with
agents on every machine you want watched.

As of the source review on **2026-09-25**, the stack is declared in
`hosts/bandit-lab/services/wazuh/default.nix` using
`virtualisation.oci-containers`. Activation evidence from **2026-09-22**
confirmed the declared units and containers. Later authenticated verification
found a green indexer with 0 unassigned shards, successful API authentication,
healthy manager core processes, and an active/current lab agent. A sample of
489 recent alerts was mostly levels 7/3 with no high/critical alerts; this is
not a full security conclusion. Dashboard browser login and alert delivery
remain unverified.

## Current ownership and paths

- Nix module: `hosts/bandit-lab/services/wazuh/default.nix`.
- Versioned configuration and public certificates:
  `hosts/bandit-lab/services/wazuh/config/` and `certs/`.
- Host state: `/srv/containers/wazuh/config/`, with tmpfiles-managed stable
  paths and symlinks into the repository assets.
- Secrets: sops declarations in the module and encrypted repository data;
  rendered files live under `/run/secrets` and `/run/secrets/rendered`.
- Containers: `wazuh.manager`, `wazuh.indexer`, `wazuh.dashboard`, and
  `wazuh.agent`, managed by generated units
  `docker-wazuh.manager.service`, `docker-wazuh.indexer.service`,
  `docker-wazuh.dashboard.service`, and `docker-wazuh.agent.service`.
- Persistent data: Docker named volumes beginning `wazuh_`; the module
  intentionally reuses the existing volume names.

The declared bindings are manager ports 1514/1515/514 on the configured
Tailscale address, manager API `127.0.0.1:55000`, indexer
`127.0.0.1:9200`, and dashboard `127.0.0.1:443`. These are source-declared
bindings, not proof that the services are currently listening.

For a later privileged verification window, use read-only checks first:

```bash
systemctl status docker-wazuh.manager.service docker-wazuh.indexer.service \
  docker-wazuh.dashboard.service docker-wazuh.agent.service
docker ps --filter name=wazuh
journalctl -u docker-wazuh.manager.service -u docker-wazuh.agent.service -b --no-pager
docker exec wazuh.manager /var/ossec/bin/agent_control -l
```

The final command requires a running container and does not, by itself, prove
authenticated dashboard/indexer health or fresh event ingestion. The
2026-09-22 activation evidence and later authenticated checks cover unit and
container state, API/indexer health, manager core processes, lab-agent status,
and the sampled alerts. Remaining verification is dashboard browser login and
alert delivery; the sampled alert count is not a full security conclusion.

## Historical Compose/bootstrap material

The following is historical migration material only. Do not run it alongside
the declarative stack: it would compete for ports and state. It records the
original certificate/setup flow and is not the current ownership model.

> **Historical status 2026-09-09:** the former external Compose project was
> observed at `/srv/containers/wazuh` and in Portainer. The steps below
> describe initial setup only; they do not describe current ownership.
> Historical deviations from the original plan: passwords lived in a `0600
> .env` next to the compose file
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

   The former stack was started with plain `sudo docker compose up -d` in
   `/srv/containers/wazuh`; this is retained only as historical evidence.

4. Verify the running containers and connected agents (container state alone
   does not prove successful ingestion):

   ```bash
   docker ps --filter name=wazuh
   docker exec wazuh-wazuh.manager-1 /var/ossec/bin/agent_control -l
   ```

   Check the dashboard for recent events from the lab agent.

## Agents and coverage

The current repository declares only the `bandit-lab` agent in the Wazuh OCI
module. The former laptop agent module was removed on 2026-09-18. Whether an
old laptop enrollment or container remains is runtime state and is not verified
by this source review.

- **bandit-lab** declares a Docker agent in the Nix-managed OCI stack.
  The manager's local identity monitors its container; it does not replace
  the host agent.
- Manager TCP ports 1514/1515 are bound to `100.125.161.81` on the tailnet.
- Host coverage comes from mounted journald data and FIM paths under `/host`.
  Inventory, rootcheck and default SCA policies run in the container's view
  of the system. Package vulnerability results therefore do not establish
  NixOS host package coverage. NixOS `/etc` symlinks into an unmounted Nix
  store also limit file-content coverage.
- The image's Amazon Linux SCA policies audit the container, not NixOS.
  Check the lab agent configuration in
  `hosts/bandit-lab/services/wazuh/config/wazuh_agent_ossec.conf` before enabling SCA
  there. Keep host vulnerability assessment in the existing
  Nix/vulnix workflow; inspect actual closures and advisories before acting.
- Journald filters use separate blocks for OR semantics and restrict ingestion
  to security-relevant sources. NixOS Samba units are `samba-smbd.service`
  and `samba-nmbd.service`, not `smbd.service` and `nmbd.service`; mirror the
  corrected filter in the separate lab agent configuration too.
- Container active response is not host firewall enforcement. CrowdSec and
  its host firewall bouncer provide that separate integration.

After an authorized lab activation, check the agent unit
(`systemctl status docker-wazuh.agent.service`) and confirm fresh host events
in the dashboard. For historical external-Compose changes,
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
