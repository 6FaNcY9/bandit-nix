# Wazuh on bandit-lab (Portainer stack)

Wazuh is the self-hosted SIEM/XDR: log ingestion, MITRE ATT&CK-mapped
detection rules, file-integrity monitoring, and vulnerability detection, with
agents on every machine you want watched.

It is deployed as a **Portainer stack**, like the Grafana/Prometheus
monitoring stack, not as in-repo `oci-containers`. Reason: the official
single-node deployment requires a TLS certificate-generation step between the
indexer, manager, and dashboard — encoding that declaratively would fight the
upstream tooling for no gain.

## Deploy the stack

1. On bandit-lab, prepare host directories:

   ```bash
   sudo install -d -m 0750 -o vino -g users /srv/containers/wazuh
   ```

2. Fetch the pinned release and generate certificates (one-time):

   ```bash
   git clone --depth 1 --branch v4.12.0 https://github.com/wazuh/wazuh-docker.git
   cd wazuh-docker/single-node
   sudo docker compose -f generate-indexer-certs.yml run --rm generator
   ```

3. In Portainer → Stacks → Add stack, paste `single-node/docker-compose.yml`.
   Before deploying, edit it:

   - Change **all default passwords** (`INDEXER_PASSWORD`,
     `API_PASSWORD`, dashboard admin) — generate them and store the dashboard
     admin password as a sops secret if you want it tracked.
   - Set the indexer heap (`OPENSEARCH_JAVA_OPTS`) to `-Xms4g -Xmx4g`; the
     lab has 64 GB, but the indexer does not need more than that for two
     hosts.
   - Do **not** publish dashboard port `443` on a routable interface. Bind it
     to loopback: `"127.0.0.1:443:443"`. Access it via SSH/Tailscale port
     forward, same as Cockpit and Portainer:

     ```bash
     ssh -L 8443:127.0.0.1:443 bandit-lab
     # → https://localhost:8443 (accept the self-signed cert)
     ```

4. Verify: `sudo docker ps | grep wazuh` — three containers (manager,
   indexer, dashboard) healthy.

## Agents

- **bandit-lab**: the manager already monitors its own host. No extra agent.
- **bandit (laptop)**: install the Wazuh agent pointing at the manager over
  the tailnet (`100.125.161.81`, port 1514/1515). If an agent package lands in
  nixpkgs, wire it into `nixos/`; until then use the upstream tarball/RPM
  manually — do not expose manager ports beyond the tailnet.

## Notes

- Resource floor: ~4 GB RAM for the indexer + ~2 GB for the rest. Fine on the
  lab; do not co-locate on anything smaller.
- Disk: plan ~50 GB for a few weeks of log retention on 4 TB NVMe.
- The dashboard stays loopback-only deliberately — a SIEM console is the
  highest-value admin target on the network; it never goes through the
  Cloudflare tunnel.
