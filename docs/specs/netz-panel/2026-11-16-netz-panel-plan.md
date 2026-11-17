# Netz-Panel Phase 1 (Sehen) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One Grafana dashboard "Netzwerk" on bandit-lab that shows what Blocky blocked per device, traffic per device (phone per app, laptop per interface), and warns over ntfy about malware lookups and new home devices.

**Architecture:** Blocky writes its query log into the lab's Postgres over the Unix socket (peer auth, 7-day retention). The Grafana container reads it as a read-only role through the mounted socket. Blocky metrics are scraped by the pod's Prometheus over the pod gateway `10.89.0.1`. The phone and a lab-side ARP watcher deliver numbers as node-exporter textfile metrics; the laptop runs a node exporter on its tailnet address. Alerts use the existing Grafana alerting → `grafana-ntfy` path.

**Tech Stack:** NixOS 26.11 flake `bandit-nix`, Blocky, PostgreSQL 16, Grafana OSS 13.0.2 + Prometheus 3.13.2 in the quadlet pod `monitoring`, node-exporter textfile collector, POSIX sh + Python 3 on the phone (Termux, root).

**Spec:** `docs/specs/netz-panel/2026-11-16-netz-panel-design.md` (decisions numbered there; "D2" = decision 2).

## Global Constraints

- Work only in the worktree `~/src/bandit-nix-netz-panel` (branch `feat/netz-panel`). The main checkout `~/src/bandit-nix` has someone else's uncommitted `services/ntopng.nix` change: never touch it.
- Commits are GPG-signed with the owner's key (pinentry on the laptop screen). Never pass `--no-gpg-sign`. If signing times out, stop and ask the owner to unlock the key.
- No push, no deploy (`lab-apply`), no sudo on any host. The owner deploys.
- On pong: nothing in `/data/adb`, no module, prop, HMA or susfs change. Boot start of the phone sender only with the owner's explicit OK.
- Blocky DNS stays on `100.125.161.81:53` only (tailnet). Port 53 is not opened on `enp44s0` in Phase 1: home devices join via Tailscale (D3); hand-set LAN DNS and the fixed LAN address (D10) wait until a device needs it.
- Query log retention: exactly 7 days (`logRetentionDays = 7`). No query log export anywhere.
- Nothing new is reachable from outside the tailnet. New listeners bind to `127.0.0.1`, `10.89.0.1` or a tailnet address only.
- Albert gets nothing in Phase 1 (his read-only org is later, D8).
- Checks: `nix build .#checks.x86_64-linux.lab-surface` and `.#checks.x86_64-linux.lab-vm` must pass. `nix flake check` already fails on lint in `desktop.nix`/`memory/dashboards.nix` on main: not this branch's problem, but add no new lint errors.
- Code comments in English, one line of why; follow the comment style of the file you edit.

## Review Focus

1. **Blocky cannot reach Postgres at boot** (Postgres starts later or the DB is missing): DNS must keep answering; only logging may stop. Owned by Task 1 (VM test restarts postgresql and checks `dig` still answers).
2. **Grafana role tries to write or delete**: must fail. Owned by Task 1 (VM test `DELETE` as `grafana` fails).
3. **Phone loses the tailnet or the lab is down while sending**: the sender must not hang, pile up processes, or leave a half-written file. Owned by Task 4 (timeout + test with an unreachable host).
4. **Stale phone or laptop numbers look current**: the dashboard must show when the last sample is older than 15 min. Owned by Task 4/5 (timestamp metric + stat panel).
5. **DNS gets slower**: mean `dig` time from the laptop must not rise more than 5 ms after deploy. Owned by Task 6 (runbook measurement before/after, rollback if worse).

---

### Task 1: Blocky query log in Postgres, read-only role for Grafana

**Files:**
- Modify: `hosts/bandit-lab/services/dns/default.nix`
- Modify: `ci/lab-surface.nix` (new asserts after the existing Blocky assert, line ~50)
- Modify: `ci/lab-vm.nix` (`nodes.lab` and `testScript`)
- Modify: `docs/runbooks/lab-dns.md` (the "No query log is kept" sentence)

**Interfaces:**
- Produces: Postgres DB `blocky`, owner role `blocky`, table `log_entries` (created by Blocky); role `grafana` (peer auth, host uid 472) with `CONNECT` on `blocky` and `SELECT` on all present and future tables in `public`. Socket dir `/run/postgresql`.

- [ ] **Step 1: Write the failing lab-surface asserts** in `ci/lab-surface.nix`:

```nix
assert lib.assertMsg (lab.services.blocky.settings.queryLog.type == "postgresql" && lab.services.blocky.settings.queryLog.logRetentionDays == 7) "Blocky must log to Postgres and keep 7 days only";
assert lib.assertMsg (lib.hasInfix "host=/run/postgresql" lab.services.blocky.settings.queryLog.target) "Blocky must reach Postgres over the Unix socket, not TCP";
assert lib.assertMsg (!(lab.services.postgresql.enableTCPIP or false)) "Postgres must not listen on TCP";
```

- [ ] **Step 2: Run** `nix build .#checks.x86_64-linux.lab-surface` → Expected: FAIL with "Blocky must log to Postgres".

- [ ] **Step 3: Implement in `services/dns/default.nix`:**
  - `queryLog = { type = "postgresql"; target = "postgres://blocky@/blocky?host=/run/postgresql&sslmode=disable"; logRetentionDays = 7; };` and replace the "No per-query log" comment with one saying why 7 days (owner request 2026-11-16, D2).
  - `services.postgresql.ensureDatabases = ["blocky"];` and `ensureUsers = [{name = "blocky"; ensureDBOwnership = true;} {name = "grafana";}];` (Postgres itself is enabled in `services/webhost`; do not move it).
  - Oneshot `systemd.services.blocky-db-grants` (after and requires the unit that runs `ensureUsers`, `postgresql-setup.service` on 26.11, else `postgresql.service`; runs as `postgres`): `GRANT CONNECT ON DATABASE blocky TO grafana`, then in `blocky`: `GRANT USAGE ON SCHEMA public TO grafana; GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana; ALTER DEFAULT PRIVILEGES FOR ROLE blocky IN SCHEMA public GRANT SELECT ON TABLES TO grafana;`
  - Blocky unit: `after`/`wants` `postgresql.service` added to the existing lists. Do not make it `requires`: DNS must answer without Postgres (Review Focus 1).

- [ ] **Step 4: Run** lab-surface → Expected: PASS.

- [ ] **Step 5: Write the failing VM test.** In `ci/lab-vm.nix` `nodes.lab` add test-only: the tailnet address on `lo` (`networking.interfaces.lo.ipv4.addresses = [{address = repoConfig.lab.tailscaleIp; prefixLength = 32;}]`, get `repoConfig` from `specialArgs`) and `services.blocky.settings.customDNS.mapping."canary.test" = "10.0.0.1";`. In `testScript`:

```python
ip = "<repoConfig.lab.tailscaleIp interpolated>"
lab.wait_for_unit("blocky.service")
lab.wait_until_succeeds(f"dig +short @{ip} canary.test | grep -x 10.0.0.1")
lab.wait_until_succeeds("sudo -u postgres psql -d blocky -tAc \"select count(*) from log_entries where question_name like 'canary.test%'\" | grep -v '^0$'", timeout=120)
lab.succeed("sudo -u grafana psql -h /run/postgresql -d blocky -tAc 'select count(*) from log_entries'")
lab.fail("sudo -u grafana psql -h /run/postgresql -d blocky -c 'delete from log_entries'")
lab.succeed("systemctl stop postgresql.service")
lab.succeed(f"dig +short @{ip} canary.test | grep -x 10.0.0.1")
lab.succeed("systemctl start postgresql.service")
```

  (Blocky flushes the log on an interval; check its `flushInterval` default and keep the 120 s timeout above it. Check the real column names with `\d log_entries` and fix the query if they differ.)

- [ ] **Step 6: Run** `nix build .#checks.x86_64-linux.lab-vm -L` → Expected: PASS (it fails before Step 3 lands; if you wrote Step 5 after Step 3, revert Step 3 once locally to see it fail).

- [ ] **Step 7: Update** `docs/runbooks/lab-dns.md`: query log is now kept 7 days in Postgres DB `blocky`; who can read it (owner via Grafana); how to wipe it (`sudo -u postgres psql -d blocky -c 'truncate log_entries'`).

- [ ] **Step 8: Commit** `feat(dns): keep Blocky's query log 7 days in Postgres, read-only for Grafana`

### Task 2: Device names, malware list, Blocky metrics in Prometheus

**Files:**
- Modify: `hosts/bandit-lab/services/dns/default.nix`
- Modify: `hosts/bandit-lab/services/monitoring/prometheus.nix` (new job after `node`)
- Modify: `ci/lab-surface.nix`, `ci/lab-vm.nix`

**Interfaces:**
- Consumes: Task 1's Blocky settings.
- Produces: denylist group `malware` (reason string in `log_entries.reason` contains `malware`); Prometheus job `blocky` scraping `10.89.0.1:4000/metrics`; client names in `log_entries.client_name`.

- [ ] **Step 1: Failing asserts** in lab-surface:

```nix
assert lib.assertMsg (lab.services.blocky.settings.ports.http == "10.89.0.1:4000") "Blocky HTTP (metrics + API) must bind the pod gateway only";
assert lib.assertMsg (lib.elem "malware" lab.services.blocky.settings.blocking.clientGroupsBlock.default) "Blocky must block the malware list for everyone";
```

- [ ] **Step 2: Run** lab-surface → FAIL.

- [ ] **Step 3: Implement** in `services/dns/default.nix`:
  - `blocking.denylists.malware = ["https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/tif.medium-onlydomains.txt"];` (checked 2026-11-16: HTTP 200, ~353k domains), `clientGroupsBlock.default = ["ads" "malware"];`
  - `ports.http = "10.89.0.1:4000"; prometheus.enable = true;`
  - Firewall like `monitoring/notify.nix:111`: `iptables -A nixos-fw -s 10.89.0.0/24 -d 10.89.0.1 -p tcp --dport 4000 -j nixos-fw-accept` plus the matching `extraStopCommands` delete. Comment: `shortcut: every container on the proxy network can reach Blocky's API (pause blocking); pin to the monitoring pod's IP if a container there is ever untrusted.`
  - Blocky needs the pod gateway address at start: add `after`/`wants` on the `proxy` network unit (`config.virtualisation.quadlet.networks.proxy.ref` gives the unit name pattern; check `systemctl list-units '*network*'` in the VM).
  - `clientLookup.upstream = "100.100.100.100";` (MagicDNS answers reverse lookups for tailnet IPs) and `clientLookup.singleNameOrder = [1];`.
- [ ] **Step 4: Add the Prometheus job** `blocky` with target `10.89.0.1:4000`.
- [ ] **Step 5: Run** lab-surface → PASS. Extend the VM test: `lab.wait_until_succeeds("podman exec prometheus wget -qO- http://10.89.0.1:4000/metrics | grep -q blocky_query_total")`. Run lab-vm → PASS.
- [ ] **Step 6: Commit** `feat(dns): malware list, device names and Prometheus metrics for Blocky`

### Task 3: Grafana Postgres datasource and the "Netzwerk" dashboard

**Files:**
- Modify: `hosts/bandit-lab/services/monitoring/alerting.nix:58-70` (add `datasources/blocky.yaml` next to `prometheus.yaml`, copied in the same `runCommand`)
- Modify: `hosts/bandit-lab/services/monitoring/default.nix` (Grafana volume `"/run/postgresql:/run/postgresql:ro"`, `unitConfig.After/Wants` add `postgresql.service`)
- Modify: `hosts/bandit-lab/services/monitoring/dashboards.nix` (new `dashboardNetzwerk`, copied as `netzwerk.json` in `grafanaDashboards`)
- Modify: `ci/lab-vm.nix`

**Interfaces:**
- Consumes: Task 1 role `grafana`, table `log_entries`; Task 2 job `blocky`; Task 4 metrics `pong_app_rx_bytes{app}`, `pong_app_tx_bytes{app}`, `pong_netstats_last_push_timestamp_seconds`; Task 5 job `laptop`.
- Produces: datasource uid `blocky-log` (type `grafana-postgresql-datasource`, host `/run/postgresql`, database `blocky`, user `grafana`, no password, `sslmode: disable`); dashboard uid `netzwerk`.

- [ ] **Step 1: Failing VM test:**

```python
lab.wait_until_succeeds("curl -fsS -u admin:$(cat /run/secrets/grafana-admin-password) http://127.0.0.1:3000/api/datasources/uid/blocky-log/health | grep -q '\"status\":\"OK\"'")
lab.succeed("curl -fsS -u admin:$(cat /run/secrets/grafana-admin-password) http://127.0.0.1:3000/api/dashboards/uid/netzwerk | grep -q Netzwerk")
```

(Use the secret path the VM really has: `config.sops.secrets."grafana-admin-password".path`; check how the existing VM test handles sops before choosing.)

- [ ] **Step 2: Run** lab-vm → FAIL (404).
- [ ] **Step 3: Implement the datasource and the volume.** If the health check fails because Grafana does not accept a socket path as host, stop and report; do not switch to TCP without the owner (Global Constraint: Postgres stays off TCP).
- [ ] **Step 4: Implement `dashboardNetzwerk`** in the style of `dashboardWanProbes` (`editable = false`, title `Netzwerk`, uid `netzwerk`, default range 24h). Panels, in this order:
  1. Stat: queries last 24h, % blocked (SQL on `log_entries`, `response_type = 'BLOCKED'`).
  2. Table: top 20 blocked domains 24h with count and devices.
  3. Time series: queries per device per hour (`client_name`), blocked stacked.
  4. Table: latest 200 queries, filtered by dashboard text variable `domain` (`question_name ILIKE '%' || '$domain' || '%'`) and variable `geraet` (multi-select from `client_name`).
  5. Table: malware hits 7 days (`reason ILIKE '%malware%'`) by device and domain.
  6. Time series: phone traffic per app, top 10 by `increase(pong_app_rx_bytes[1h]) + increase(pong_app_tx_bytes[1h])`.
  7. Stat: age of phone data `time() - pong_netstats_last_push_timestamp_seconds`, red above 900 s; same for laptop `time() - max(timestamp(up{job="laptop"} == 1))`.
  8. Time series: laptop rx/tx `rate(node_network_receive_bytes_total{job="laptop",device!~"lo|tailscale0"}[5m])` and transmit.
  9. Text panel with links: ntopng, Beszel (PCs albert/slayer), CrowdSec note "IP-Bans schützen nur das Lab" (D11). Use the svc URLs from `tailnet-https.nix` (`https://<name>.<tailnet>.ts.net`).
- [ ] **Step 5: Run** lab-vm → PASS.
- [ ] **Step 6: Commit** `feat(monitoring): Netzwerk dashboard with Blocky log datasource`

### Task 4: Phone sender (pong) and its lab-side file

**Files:**
- Create on the phone: `~/projects/pong-netstats/netstats.py`, `~/projects/pong-netstats/test_netstats.py`, `~/projects/pong-netstats/fixtures/netstats-detail.txt` (trimmed real `dumpsys netstats detail` output, anonymise `subscriberId`), `~/projects/pong-netstats/send.sh`, `~/projects/pong-netstats/README.md`
- Modify (repo): `hosts/bandit-lab/services/monitoring/default.nix` tmpfiles: `"f /var/lib/node-exporter-textfile/pong.prom 0644 vino users -"`
- Modify: `ci/lab-surface.nix`

**Interfaces:**
- Produces (Prometheus text): `pong_app_rx_bytes{app="<package or uid>"}` and `pong_app_tx_bytes{app=...}` (counters, bytes since the phone's netstats history starts), `pong_netstats_last_push_timestamp_seconds` (gauge, Unix time).
- `netstats.py`: `parse_uid_totals(text: str) -> dict[int, tuple[int, int]]` (uid → (rx, tx) summed over all buckets of the `UID stats` section); `uid_names(text: str) -> dict[int, str]` (from `cmd package list packages -U`, several packages on one uid joined with `+`); `render(totals, names, now: int) -> str`. CLI: `su -c 'dumpsys netstats detail'` and `su -c 'cmd package list packages -U'` piped in by `send.sh`, prints the file to stdout.

- [ ] **Step 1: Failing tests** (`cd ~/projects/pong-netstats && python3 -m unittest test_netstats`): parse the fixture → a known uid has the summed `rb`/`tb` you computed by hand from the fixture; `ident` lines with `uid=-1` are ignored; `render` output contains `pong_netstats_last_push_timestamp_seconds 1794850000` for `now=1794850000` and every label value is escaped (`"` and `\`).
- [ ] **Step 2: Run** → FAIL (module missing).
- [ ] **Step 3: Implement** `netstats.py` (stdlib only).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Implement `send.sh`**: every 300 s: build the file, then send it with `timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=10 lab 'cat > /var/lib/node-exporter-textfile/pong.prom'` (in place: the directory is root-owned, so no temp file + `mv`). Comment `shortcut: in-place write can be read half-done by one scrape; move to a vino-owned subdir + symlink if scrapes show parse errors.` A lock file (`flock -n`) stops a second copy. Test by hand with host `lab` unreachable (`ssh -o HostName=192.0.2.1`): returns within 25 s, no leftover processes.
- [ ] **Step 6: Lab side**: tmpfiles line above; lab-surface assert that it exists with mode `0644` and owner `vino`. Run lab-surface → PASS.
- [ ] **Step 7: README.md** in the phone project: what it sends, start/stop (`nohup sh send.sh &`, `pkill -f pong-netstats/send.sh`), and that boot start (a line in the dnsfilter `run.sh` or `/data/adb/service.d`) needs the owner's OK.
- [ ] **Step 8: Commit** the repo part `feat(monitoring): textfile slot for the phone's per-app traffic`. The phone files are not in a repo: list them in the task report.

### Task 5: Laptop traffic and alerts

**Files:**
- Modify: the laptop host config (find where `hosts/bandit` sets services; add `services.prometheus.exporters.node` with `listenAddress = <laptop tailnet IP from repoConfig>`, `enabledCollectors = ["netdev"]`, firewall `tailscale0` TCP 9100 only)
- Modify: `hosts/bandit-lab/services/monitoring/prometheus.nix` (job `laptop`, target `<laptop tailnet IP>:9100`)
- Create: `hosts/bandit-lab/services/monitoring/netwatch.sh`, `netwatch.test.sh`, `netwatch.nix` (imported from `monitoring/default.nix`)
- Modify: `hosts/bandit-lab/services/monitoring/alerting.nix` (one Grafana rule)
- Modify: `ci/lab-surface.nix`

**Interfaces:**
- Consumes: datasource `blocky-log` (Task 3), `ntfyEnv` pattern from `notify.nix`.
- Produces: alert rule "Malware-Anfragen" (fires when one `client_name` has ≥ 20 rows with `reason ILIKE '%malware%'` in 10 min); unit `lab-netwatch` (timer 2 min) that sends ntfy "Neues Gerät im Heimnetz: <MAC> <IP>" for a MAC on `enp44s0` not seen before; state file `$STATE_DIRECTORY/known-macs`.

- [ ] **Step 1: Failing `netwatch.test.sh`** in the style of `aiia-create/stats.test.sh`: feed `ip -j neigh show dev enp44s0` fixtures through `netwatch.sh` with `NTFY_URL` pointing at a stub (a `curl` shim on `PATH` that records calls). Assert: first run with 3 MACs records them and sends **nothing** (bootstrap); second run with one new MAC sends exactly one message containing that MAC; `FAILED`/`INCOMPLETE` entries are ignored; a third identical run sends nothing.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `netwatch.sh` (`writeShellApplication`, inputs iproute2, jq, curl, coreutils) and `netwatch.nix` (service + timer, `DynamicUser`, `StateDirectory = "lab-netwatch"`, ntfy env as in `notify.nix`). Wire the test as a check like the aiia stats test is wired.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Laptop exporter + `laptop` job.** lab-surface stays green (lab-only). Evaluate the laptop: `nix build .#nixosConfigurations.bandit.config.system.build.toplevel --dry-run`. Owner step for the runbook: tailnet policy must allow `tag:lab` → bandit TCP 9100; without it the stat panel shows the data as stale (Review Focus 4), nothing breaks.
- [ ] **Step 6: Alert rule** in `alerting.nix` with the SQL datasource, `for: 0m`, label `severity = "warning"`; `grafana-ntfy` forwards it unchanged. VM test: insert 20 fake malware rows for client `testgeraet` as `postgres`, wait until `/api/prometheus/grafana/api/v1/alerts` lists "Malware-Anfragen" firing.
- [ ] **Step 7: Run** lab-vm and lab-surface → PASS.
- [ ] **Step 8: Commit** `feat(monitoring): laptop traffic, malware alert and new-device watcher`

### Task 6: Runbook, speed check, rollback

**Files:**
- Create: `docs/runbooks/lab-netz-panel.md`

- [ ] **Step 1: Write the runbook**: what the panel shows and where (`https://grafana.<tailnet>.ts.net/d/netzwerk`); owner steps after deploy (tailnet grant for laptop:9100; start the phone sender; check that Cloudflare Access on `grafana.atmosphaere.at` lets only the owner in, else remove that route before trusting the DNS log there); the speed check; rollback per part (copy the "Rückweg" list from the spec, with exact commands).
- [ ] **Step 2: Speed check commands** in the runbook, run by the owner before and after deploy from the laptop: `for i in $(seq 50); do dig @100.125.161.81 example.org +noall +stats | awk '/Query time/{print $4}'; done | awk '{s+=$1} END {print s/NR " ms"}'` (both runs hit a warm cache for example.org, so they compare fairly). Rule: after − before > 5 ms → roll back Task 1 first (query log off) and measure again.
- [ ] **Step 3: Commit** `docs(runbooks): netz-panel owner steps, speed check and rollback`
