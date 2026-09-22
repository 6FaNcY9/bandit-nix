# Bandit-lab handoff — 2026-09-09

This is a continuation checkpoint for another model/tool. Read this file before changing anything.

## Goal

Improve and, where evidence supports it, refactor the existing `bandit-lab` services and applications. Priorities are service reliability, the Mrija archive UI/integration, and the already-running Docker/Nix services. Keep changes small, reversible, and evidence-based.

## Authority and hard limits

- Local repository edits are authorized.
- SSH access to `bandit-lab` is authorized **read-only**. Do not run commands that write, restart, deploy, pull images, mutate Docker state, change Cloudflare, alter secrets, or reset/delete Vaultwarden data.
- Do not reset the forgotten Vaultwarden master password. Vaultwarden cannot decrypt the old vault after a password reset; first export/copy from Bitwarden and verify attachments/clients. Destructive account replacement requires a separate explicit decision.
- Do not edit or revert unrelated dirty files: `AGENTS.md` and `docs/runbooks/aiia-shop.md`.
- Do not claim a deployment, reboot, remote push, or live activation without direct evidence.

## Repository state at handoff

Working tree was:

```text
## main...origin/main
 M AGENTS.md
 M docs/runbooks/aiia-shop.md
```

Those two files are pre-existing user changes. Recent relevant commits, newest first:

```text
5b2a96b feat(monitoring): add direct origin probes
816bf1a fix(lab): handle runtime secret rotation
a68579c ci: upload partial builds to Cachix
8157ecb chore(secrets): replace invalid cloudflare-api-key with scoped API token (7d expiry)
d77232d feat(secrets): wire cloudflare-api-key into shells as CLOUDFLARE_API_TOKEN
78948e2 fix(bandit-lab): allow AF_INET in docker proxy sandbox for HAProxy QUIC probe
493b16e feat(bandit-lab): harden updater, Docker discovery, and deploy gating
```

## Verified remote facts

Connect read-only through Tailscale:

```bash
rtk proxy ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=8 \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/home/vino/.ssh/known_hosts \
  -o IdentitiesOnly=yes -i /home/vino/.ssh/homelabKey \
  vino@100.125.161.81 'READ_ONLY_COMMANDS'
```

The health check passed but reported two failed non-critical units:

```text
docker-aiia-ghost.service loaded failed failed docker-aiia-ghost.service
mrija-archive-sync.service loaded failed failed Trigger mrija-archive daily mail sync
```

Ghost failure evidence:

```text
create table `migrations_lock` (...) default character set utf8mb4
Got error 168 - 'Unknown (generic) error from engine' from storage engine
errno1030 sqlStateHY000
```

MySQL evidence:

```text
[MY-012592] [InnoDB] Operating system error number 13 in a file operation.
[MY-012595] [InnoDB] The error means mysqld does not have the access rights to the directory.
[MY-012894] [InnoDB] Unable to open './#innodb_redo/#ib_redo9' (error: 1000).
```

The host had ample disk space (about 2.4T free, 3% used). `/srv/containers/aiia/mysql` was observed as mode `750`, owner `1000:100`. The likely cause is a UID/GID mismatch between the Nix tmpfiles ownership and the MySQL container, but this must be confirmed before editing.

At the time of the original audit, the archive endpoint answered locally with HTTP 303. The archive container had no recent log output. The daily sync service exited with status 28 after its 30-second POST timeout; this was a historical failure and is superseded by the verified end-to-end repair documented below.

## Relevant source locations

- MySQL/Ghost declaration: `hosts/bandit-lab/aiia.nix`
- Archive container and sync unit: `hosts/bandit-lab/mrija-archive.nix`
- Cloudflare tunnel declaration: `hosts/bandit-lab/wan.nix`
- Vaultwarden declaration: `hosts/bandit-lab/vaultwarden.nix`

`aiia.nix` currently creates the MySQL directory with the host user/group:

```nix
"d /srv/containers/aiia/mysql 0750 ${username} users -"
```

The MySQL image is pinned to `mysql:8.4` by digest and mounts `/srv/containers/aiia/mysql:/var/lib/mysql`.

The archive unit runs as `vino`, posts to `http://127.0.0.1:8081/api/sync` with `X-API-Key`, expects JSON `.status == "started"`, then waits on the progress SSE stream. Its POST timeout is 30 seconds and the complete run has a 35-minute unit timeout.

The real archive source is outside this writable repo at `/home/vino/Projects/mrijaPageClean`; an older snapshot in `/tmp/bandit-lab-archive-reliability` is available for comparison only. Historical integration concerns include run-specific status, stale completion, and authoritative success reporting. Do not invent UI changes while the actual UI source is unavailable.

## Vaultwarden / Cloudflare context

The configured browser URL is `https://vault.bandit-lab.mrija.org`. The Cloudflare Access application screenshot showed destination `vaultwarden.bandit-lab.mrija.org` with policy `vino-allow`; other self-hosted apps are configured similarly. Tunnel UUID: `4e76764f-e936-4984-a62a-a43ad0151afe`.

Cloudflare Access is an interactive browser gate. Native Vaultwarden clients may still fail because API/sync traffic needs a compatible authentication path; verify the exact client behavior before changing DNS, tunnel, or Access policy. A Cloudflare token exists in the environment, but this handoff authorizes no Cloudflare writes.

## Next steps, in order

1. **Read-only runtime confirmation.** Run only inspection commands:

   ```bash
   docker inspect aiia-mysql --format '{{json .Config.User}} {{json .State.Pid}} {{json .Mounts}}'
   docker exec aiia-mysql id mysql
   docker exec aiia-mysql stat -c '%a %u:%g %n' /var/lib/mysql /var/lib/mysql/#innodb_redo
   journalctl -u docker-aiia-ghost.service -u mrija-archive-sync.service --since '2 hours ago' --no-pager
   curl -i --max-time 10 http://127.0.0.1:8081/
   ```

2. **Choose the smallest source fix from evidence.** If the container UID cannot write the mounted directory, adjust only the MySQL tmpfiles ownership in `hosts/bandit-lab/aiia.nix` (likely leave ownership to the container with `- -`), then document that the existing remote directory still needs a one-time operator ownership correction. Do not perform that correction remotely in this session.

3. **Trace archive timeout before changing it.** Confirm whether `/api/sync` itself exceeds 30 seconds, whether the API returns `started`, and whether the worker reaches a terminal state. Only then change the timeout or source integration. Do not hide a failing sync by extending a timeout blindly.

4. **Validate local changes.** At minimum:

   ```bash
   nix run nixpkgs#alejandra -- --check hosts/bandit-lab/aiia.nix hosts/bandit-lab/mrija-archive.nix
   git diff --check
   nix flake check --no-update-lock-file
   ```

   If the Nix daemon, network, or secrets block a check, record the exact failure and do not present static checks as live validation.

5. **Do not deploy automatically.** Stop with a reviewable diff and an explicit operator checklist. A later authorized session can rebuild/switch, repair ownership, verify `bandit-lab-health`, and inspect Ghost/archive recovery.

## Known tooling note

`/graphify` is not a Codex slash command. `graphify code install` already installed its hook and `AGENTS.md`; the binary is `/home/vino/.local/bin/graphify`. Use `graphify update .` after code changes if the next tool supports it.

## Handoff acceptance checklist

- [x] Existing `AGENTS.md` and `docs/runbooks/aiia-shop.md` changes preserved.
- [x] MySQL UID/GID and mounted directory permissions confirmed read-only.
- [x] Archive timeout cause distinguished from a generic service failure.
- [x] Any patch limited to the smallest evidence-backed files.
- [x] Formatter, diff check, and flake check results recorded.
- [x] No remote mutation, Cloudflare write, Vaultwarden reset, deployment, or reboot performed.

---

# Continuation results — second session, 2026-09-09

## MySQL / Ghost: root cause confirmed and source fix applied

Read-only inspection confirmed the hypothesis:

- `aiia-mysql` runs with no `Config.User` override; the image entrypoint drops to `uid=999 gid=999 (mysql)`.
- The bind mount `/srv/containers/aiia/mysql` was `750 1000:100` (`vino:users`). UID 999 is "other" on that directory and gets zero permissions, so `mysqld` cannot even traverse its own datadir: InnoDB reports `Operating system error number 13` and `Unable to open './#innodb_redo/#ib_redo9'`. All files *inside* the datadir are correctly `999:999` — only the top-level directory is wrong, because the tmpfiles `d` rule re-applies `${username}:users` after every boot.
- Ghost's `create table migrations_lock ... errno 1030 / Got error 168` crash loop is a direct downstream symptom of the same EACCES; `docker-aiia-ghost.service` hit `start-limit-hit`. No Ghost-side change needed.

Source fix (this session): `hosts/bandit-lab/aiia.nix` now declares the MySQL dir as `"d /srv/containers/aiia/mysql 0750 - - -"` so tmpfiles only creates it if missing and never re-owns it; the image entrypoint chowns the datadir itself. The existing remote directory still needs the one-time operator correction below — the Nix change prevents recurrence, it does not repair the current host.

## Archive sync: verified complete on 2026-09-22

- TheHost SSH uses the rotated ED25519 key and a pinned ECDSA host key in the dedicated read-only `known_hosts` mount.
- The supervised service now completes the full POST → SSE → rsync → reindex path with strict SSH checking; the latest verified run indexed 29,750 emails and exited `0/SUCCESS`.
- The daily timer is enabled and scheduled for 03:00 CEST.
- Docker DNAT required the service sandbox to allow the external proxy subnet `172.18.0.0/16` while retaining `IPAddressDeny=any`.
- The API key is loaded through a systemd credential, passed through a temporary mode-600 header file, and is no longer present in the service environment or curl process arguments.

## Security observation (remaining)

The external Compose deployment still supplies `MRIJA_API_KEY` and `MRIJA_PASSWORD` as
container environment variables, which Docker exposes to users with host Docker access
via `docker inspect`. The service-side API-key argv and environment exposure are
fixed with a systemd credential; migrating the external application to
file-backed secrets remains a separate hardening task. The currently deployed image
only reads the direct variables and has no `*_FILE` support, so removing `env_file`
now would break authentication or trigger its generated development-key path.

Application-side support for strict file-backed credentials is prepared locally in
the separate `mrija-archive` checkout as commit `60ac9a7`; syntax and credential
helper checks pass, but its focused pytest run needs the missing offline FastAPI
dependencies. The image has not been rebuilt, published, or deployed.

The safe migration is coordinated: add strict file-backed credential loading to the
application (including API validation, password login, startup, and templates), build
and pin a tested image, then update the authoritative Portainer stack to mount only
the two individual secret files read-only and set `MRIJA_API_KEY_FILE`/
`MRIJA_PASSWORD_FILE`. Acceptance requires file-only startup, fail-closed missing or
conflicting credentials, authenticated API/login checks, no sentinel values in
`Config.Env`, argv, logs, or image layers, and a recreate-plus-rotation test. Do not
introduce a competing Nix-managed container or mount all of `/run/secrets`.

## Validation (this session)

- `nix run nixpkgs#alejandra -- --check hosts/bandit-lab/aiia.nix hosts/bandit-lab/mrija-archive.nix` — pass.
- `git diff --check` — pass.
- `nix flake check --no-update-lock-file` — pass.
- No remote mutation, deployment, reboot, Cloudflare write, or Vaultwarden action was performed. Remote access was read-only inspection only (docker inspect/exec stat+ls, journalctl, curl GET, ssh auth probe with `BatchMode` and `UserKnownHostsFile=/dev/null`).

## Operator checklist (requires a separately authorized session)

1. AiiA MySQL directory ownership repair is deployed declaratively; `docker-aiia-mysql.service` and `docker-aiia-ghost.service` are active with clean recent logs.
2. MRIJA archive sync and its daily timer are verified complete as documented above.
3. Run `bandit-lab-health` after future service changes and confirm zero failed units.

---

# Continuation results — third session, 2026-09-09 (security-lab build-out)

Governing spec: `docs/specs/2026-09-09-security-lab.md`. All phases deployed
via signed commits + `lab-update apply` (health-gated, rollback-safe).

## Phase 1 — quick hardening (627c050)

SearXNG Traefik rateLimit middleware, WatchYourLAN cleanup, Jellyfin removed.

## Phase 2 — Wazuh SIEM (b1d5a42)

Wazuh manager/indexer/dashboard stack running (docker, all up).

## Phase 3 — CrowdSec IDS/IPS (f56b645 → 6db8bc1)

- Engine v1.7.8: journald sshd acquisition + file-based Traefik access-log
  acquisition (`/var/log/traefik/access.log`, logrotate copytruncate).
  Verified parsing and bucket pours. CAPI enrolled; community blocklist
  (~15k IPs) pulled; sharing on.
- Firewall bouncer: iptables/ipset DROP in `CROWDSEC_CHAIN`, hooked into
  both `INPUT` and `DOCKER-USER` (published container ports covered too).
- Traefik bouncer plugin (maxlerebourg v1.7.1) on the `web` entrypoint.
  **Bootstrap lesson:** the plugin option MUST be `crowdsecLapiKeyFile` —
  `crowdsecLapiKey` is sent verbatim as X-Api-Key; pointing it at the sops
  path made every LAPI call 403 and every request fail closed, which
  rolled the first remediation deploy back via the health gate's HTTP probes.
- End-to-end ban test verified: `cscli decisions add --ip X` → request via
  Traefik with that X-Forwarded-For → 403; clean IP → 200.

## Phase 4 — analyst toolbox (a7dc331, e9f59c3)

`hosts/bandit-lab/toolbox.nix`: juice-shop, cyberchef (port 8080!), it-tools
on the proxy network behind Traefik. All three verified 200 via Traefik and
302 → Cloudflare Access publicly (unauthenticated by design, Access-gated).
Tunnel ingress + CNAMEs + Access apps done via Cloudflare API.

## Hardening add-ons (96b7fe8, Cloudflare)

- `crowdsec.service` + `crowdsec-firewall-bouncer.service` added to
  health-check criticalUnits — a dead engine/bouncer now rolls back deploys.
- Cloudflare Access app created for `aiia.at/ghost` (Ghost admin panel was
  internet-exposed with only Ghost's own login). vino-allow policy.

## Deferred / open

- aiia `mail__from` still points at a stale domain; outbound SMTP is
  impossible (ISP blocks 25/465/587/2525/2587, dynamic PTR, tunnel-only
  inbound). Any mail must go via an HTTP-API relay (provider choice pending).
- Public email server verdict is FINAL: impossible on this connection.
- Vaultwarden admin token Argon2 hardening (LOW).
- `ensure-*-network` script dedup (cosmetic).
- Spec phase 5 (Gophish + maddy internal phishing-sim, Kasm Workspaces) —
  explicitly optional, not started.
- MRIJA container environment secrets remain a hardening follow-up; see the archive
  security observation above.

## Wazuh SIEM session (evening) — 4.12.0 → 4.14.7, agents, tuning

Stack lives at `/srv/containers/wazuh/` (compose, still NOT repo-managed).
Backup of the old stack: `/srv/containers/wazuh.bak-4.12.0`.

### Upgrade 4.12.0 → 4.14.7

- Indexer config mount paths changed upstream: everything now under
  `/usr/share/wazuh-indexer/config/{certs,opensearch.yml,opensearch-security/...}`
  — fixed in `docker-compose.yml` AND the cert paths inside
  `config/wazuh_indexer/wazuh.indexer.yml`.
- Dashboard: global dark mode via saved-objects API
  (`POST /api/opensearch-dashboards/settings/theme:darkMode`), branding title
  "bandit-lab SIEM" in `config/wazuh_dashboard/opensearch_dashboards.yml`.
  Custom CSS colors (Gruvbox) are NOT supported by OpenSearch Dashboards.
- Manager agent ports 1514/1515 + 514-udp rebound from 0.0.0.0 to the
  Tailscale IP `100.125.161.81` only; 55000/9200 stay on loopback.

### Agent architecture (hard-won lessons)

- **Both hosts run the `wazuh/wazuh-agent` container.** bandit-lab: compose
  service `wazuh.agent`. bandit laptop: `nixos/wazuh-agent.nix` (podman
  oci-container, commits 4f64ae7, 0536260).
- **docker-listener wodle needs the python `docker` package**, missing from
  the agent image. `import docker` silently resolved to the wodle's own dir
  as a namespace package. Fix: `pip install --target` (via throwaway
  `python:3.9-slim`) into `config/wazuh_agent/site-packages`, mounted at
  `/usr/local/lib64/python3.9/site-packages:ro` (first in sys.path, empty in
  the image). PYTHONPATH does NOT propagate through s6 to modulesd.
- **Unfiltered journald localfile congests the agent queue.** NixOS docker
  log-driver=journald → the entire host journal (all Traefik access logs)
  was forwarded; the wodle blocked on `s.send()` to the full unix-dgram
  queue. Fix: filtered journald blocks only — `_SYSTEMD_UNIT` =
  sshd/systemd-logind/fail2ban/smbd/nmbd, `_COMM` = sudo, `PRIORITY` 0-3.
  Filter semantics: multiple `<localfile>` blocks OR; filters within a block
  AND; `ignore_if_missing="yes"` accepts logs lacking the field.
- **Duplicate-name enrollment:** `docker compose up -d` recreates wipe
  `/var/ossec/etc` → re-enroll → manager rejects duplicate. Fix: manager
  `<auth><force_insert>yes</force_insert><force_time>0</force_time>` +
  named volume `wazuh_agent_etc:/var/ossec/etc` (client.keys persists).
  NOTE: the manager's `/var/ossec/etc` is itself a named volume
  (`wazuh_etc`); `docker restart` did NOT re-copy the config-mount — had to
  `docker exec cp /wazuh-config-mount/etc/ossec.conf /var/ossec/etc/ossec.conf`
  + restart. Old duplicate agent 001 was auto-replaced by new ID 003.
- **ossec.conf ownership on the laptop:** files seeded into
  `/var/lib/wazuh-agent/etc` must be group 999 (image wazuh group);
  root:root broke wazuh-agentd with "Error reading XML (line 0)".
- The lab agent's `0-wazuh-init: exited 1` on start is cosmetic (unset
  WAZUH_REGISTRATION_PASSWORD makes the last `&&` chain return 1).

### FIM tuning

- Default 100k file_limit was exceeded (level-12 alerts) because
  `/host/srv/containers` includes the docker data-root (~637k files in
  overlay2 etc.) plus ~296k `.git`/`node_modules` files. Fix:
  `file_limit` 500k + ignores `^/host/srv/containers/docker`, `.git/`,
  `node_modules`. No limit warnings since.

### Data analysis (erste Auswertung)

- Agents: 000 manager, 002 bandit (laptop), 003 bandit-lab — all Active.
  Alerts 24h: bandit-lab 457, manager 190, bandit 189.
- Level distribution 24h: 622× lvl3, 187× lvl7, 21× lvl5, 6× lvl4, 2× lvl12
  (the lvl12 were the FIM-limit events, fixed).
- 737 of 838 alerts (24h) are **SCA noise**: CIS Benchmark for Amazon Linux
  2023 — the agents scan their CONTAINER OS, not the NixOS hosts. Host
  packages/kernel are invisible to this setup (score ~52-53%, mostly
  container-irrelevant checks like AIDE/auditd/nftables).
- **Zero sshd brute-force alerts in 7 days** (SSH is tailscale/LAN-only +
  fail2ban). The web/accesslog flood seen during debugging never reached the
  indexer (dropped by the congested queue — that WAS the root-cause proof).
- docker-listener live: container exec/volume events flowing (mostly
  cadvisor/vaultwarden healthchecks, lvl3).
- Vulnerabilities (container image, 4 per agent): **CVE-2026-14456 High**
  (openssl-libs + openssl-fips-provider 3.5.7 amzn2023) — watch for a fixed
  `wazuh/wazuh-agent` image; python3-pip-wheel CVE-2026-45409/9375 Medium.
- Dashboard "no agents registered" card was stale cache → hard-refresh.

### Open

- ~~Wazuh stack not repo-managed~~ → done, see next section.
- Consider pinning agent image updates to pick up the openssl CVE fix.

## Wazuh repo-managed (3c9822b) — compose → oci-containers

The stack at `/srv/containers/wazuh/` is now declarative:
`hosts/bandit-lab/wazuh.nix` runs manager/indexer/dashboard/agent as
`virtualisation.oci-containers` on a dedicated `wazuh` docker network,
reusing the existing compose named volumes (zero data migration). Portainer
sees all four containers like every other unit on the host.

- Configs + public certs versioned under `hosts/bandit-lab/wazuh/`, symlinked
  to stable paths via tmpfiles `L+`.
- Passwords (`wazuh-admin-password` = indexer admin, `wazuh-api-password`,
  `wazuh-dashboard-password`), all TLS private keys, and
  `internal_users.yml` (password hashes) are sops secrets in
  `secrets/secrets.yaml`. Node/admin keys mount from `/run/secrets`; the CA
  keys render back into the certs dir so the upstream cert-regeneration
  compose file keeps working.
- Indexer/dashboard containers read uid 1000 → sops owner `vino` (uid 1000
  on this host). Grafana-style system-user trick unnecessary here.
- Dashboard `wazuh.yml` ships upstream with a plaintext API password →
  rendered via sops template, never committed.
- Agent `site-packages` (pip `docker` package for the docker-listener wodle)
  stays host state at `/srv/containers/wazuh/config/wazuh_agent/site-packages`;
  regenerate on a fresh host with
  `docker run --rm -v <dir>:/out python:3.9-slim pip install --target /out docker`.
- The old `docker-compose.yml` + `generate-indexer-certs.yml` remain on the
  host as inert files; `.env` (plaintext passwords) was removed after
  verification.
