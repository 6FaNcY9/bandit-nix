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

The archive endpoint answered locally with HTTP 303. The archive container had no recent log output. The daily sync service exited with status 28 after its 30-second POST timeout; whether the API is slow, unavailable, or returning an unexpected response is not yet proven.

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

## Archive sync: timeout cause traced, no repo change made

- Every daily run Aug 26 → Sep 9 failed identically: POST `/api/sync` produced no response within the 30 s curl timeout (exit 28). Earlier runs Aug 21–24 failed fast with status 1.
- The archive API is healthy and fast: `GET /` → 303 in ~1 ms; authenticated `GET /api/update/progress` → 200 in 0.19 s, but returns a stale `{"percent": 100, "status": ""}` (last real index write was Aug 26).
- Root cause is upstream: from inside the container **and** from the host, `ssh -i /home/vino/.ssh/thehost_mrija mrija_org@s16.thehost.com.ua` fails with `Permission denied (publickey,password)`. The mounted key and host key are the same key (fingerprint `SHA256:SQ/wg+BBurOECFUlodP2OpGFelRYAg/5mmlb4VpoANE`), so the remote server no longer accepts it. The `/api/sync` handler blocks on this dead SSH path longer than the 30 s POST timeout.
- Conclusion: extending the sync unit's timeout would only hide the failure — `hosts/bandit-lab/mrija-archive.nix` was intentionally left unchanged. The fix is restoring the key on the mail host (or provisioning a new key), which is outside this repo and outside read-only authorization.

## Security observation (no action taken)

The `deploy-mrija-archive-1` container (docker-compose managed, not declared in this repo) has `MRIJA_API_KEY` and `MRIJA_PASSWORD` baked into `Config.Env` in plaintext — readable by anyone with host docker access via `docker inspect`. Consider moving the compose project to an env file with `0400` perms or to the sops-managed path in a future session.

## Validation (this session)

- `nix run nixpkgs#alejandra -- --check hosts/bandit-lab/aiia.nix hosts/bandit-lab/mrija-archive.nix` — pass.
- `git diff --check` — pass.
- `nix flake check --no-update-lock-file` — pass.
- No remote mutation, deployment, reboot, Cloudflare write, or Vaultwarden action was performed. Remote access was read-only inspection only (docker inspect/exec stat+ls, journalctl, curl GET, ssh auth probe with `BatchMode` and `UserKnownHostsFile=/dev/null`).

## Operator checklist (requires a separately authorized session)

1. `sudo chown 999:999 /srv/containers/aiia/mysql` on bandit-lab (one-time repair; the tmpfiles fix in this diff prevents recurrence after reboot).
2. `sudo nixos-rebuild switch --flake .#bandit-lab`, then confirm `docker-aiia-mysql.service` and `docker-aiia-ghost.service` start and Ghost finishes its migrations.
3. Restore SSH access for `mrija_org@s16.thehost.com.ua` (re-add the `mrija-thehost-unattended` public key on the mail host or issue a new keypair and update the sops `thehost-sshkey` secret + `/home/vino/.ssh/thehost_mrija`). Then run `sudo systemctl start mrija-archive-sync.service` and verify it exits 0 and the sqlite index mtime advances.
4. Run `bandit-lab-health` and confirm zero failed units.
