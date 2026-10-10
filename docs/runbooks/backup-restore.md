# Backup restore verification

Restore testing is separate from archive-integrity testing. The current
archives have passed gzip/tar checks and checksum verification, but no live
database or world has been replaced.

## PostgreSQL

Run only during an approved maintenance window, using a temporary data
directory and a non-production port:

1. Copy `all.sql.gz` to private temporary storage without changing the source.
2. Initialize a temporary PostgreSQL cluster owned by `postgres`.
3. Start it on an unused loopback port, restore the dump with `psql`, and
   confirm that the expected databases and roles exist.
4. Stop the temporary instance, remove only the temporary directory, and
   record the restore result.

This proves that the dump can be imported into the tested PostgreSQL version;
it does not prove application-level recovery or off-host recoverability.

## Minecraft

Deployed with the panel change (`40a947e`, 2026-10-06): `minecraft-backup.timer` (03:40)
writes a consistent archive (`save-off`, `save-all flush`, rsync, `save-on`, tar.zst)
with a `.sha256` and keeps the newest 14 in `/srv/containers/minecraft/backups/auto`;
the restic job calls the same snapshot script. `tools/minecraft-restore-test.sh
ARCHIVE` is the restore drill (new directory, throwaway container, no published
port). The manual procedure below stays valid for cold backups.

1. Make a fresh consistent backup after `save-all flush` and a graceful stop.
2. Extract a copy into an isolated temporary directory; never extract over
   `/srv/containers/minecraft/data`.
3. Verify the world directory, `level.dat`, player data, plugins, and archive
   ownership/modes.
4. If gameplay validation is approved, start a separate temporary Paper
   instance with no production port or network exposure.
5. Remove only the temporary copy after recording the result.

This proves archive extraction and, if the temporary instance is tested, basic
world startup. It does not prove that a production replacement is safe.

## Off-host backups (restic to Backblaze B2)

Decision D7 (2026-10-06). Module: `hosts/bandit-lab/services/backup/default.nix`,
disabled until the secrets exist. Evaluated in its enabled form by the
`lab-backup` flake check.

| What | How it is captured |
| --- | --- |
| Vaultwarden data | files copied, plus an online `sqlite3 .backup` snapshot of `db.sqlite3` |
| AiiA / Ghost database | `mysqldump --single-transaction --all-databases` inside the container (password stays in the container's environment) |
| AiiA / Ghost content | `/srv/containers/aiia/content-{images,media,files,data}` |
| PostgreSQL | the existing 03:15 dumps in `/var/backup/postgresql` |
| Mrija archive | `maildir/` plus an `sqlite3 .backup` snapshot of `mail_index.sqlite` |
| Minecraft (once the panel change is deployed) | `minecraft-snapshot`: saves flushed and frozen while rsync copies the data directory (worlds, plugins, panel accounts), then re-enabled; excludes caches, logs, panel backups, BlueMap tiles |

Not included on purpose: Portainer (retired; local rollback archive exists),
`/srv/storage` (Samba share), Grafana/Prometheus data and the
Wazuh indexer. Add a path in the module if you want one of them.

Schedule: backup daily 04:30 (random delay up to 20 minutes), retention 7 daily,
5 weekly, 12 monthly, 2 yearly, integrity check every Sunday 06:00 (repository
structure plus a rotating 5 % of the data). Staging lives in
`/var/backup/restic-staging` (root only) and is emptied after every run.

### Enabling it (owner, one time)

1. **Backblaze:** create a private bucket and an application key restricted to
   that bucket (read, write, delete; restic needs delete to prune). Note the
   keyID and the applicationKey: B2 shows the key only once.
2. **Add the four secrets** to `secrets/lab.yaml` with the prompt-driven helper
   (nothing is echoed; it can generate the repository password and makes you
   save it offline first):
   ```bash
   cd ~/src/bandit-nix && bash tools/add-backup-secrets.sh
   ```
   The repository password is the key to every backup: store a copy outside
   the lab (a password manager on another device, or paper).
3. **Check:** `nix flake check --no-update-lock-file` (the `sops-isolation`
   check confirms the keys exist in `lab.yaml`).
4. **Switch it on:** set `bandit-lab.backups.enable = true;` in
   `hosts/bandit-lab/default.nix`, commit signed, push, and apply with
   `sudo lab-update apply`.
5. **Let monitoring see it:** the Compose node-exporter flags and the Grafana
   alert rules changed in the same release, and `compose-monitoring.service`
   only *starts* existing containers, so `lab-update` never applies them. Force
   the two containers to be recreated (Grafana reads its provisioned alert
   files only when it starts):
   ```bash
   sudo docker compose -p monitoring -f /etc/bandit-lab/monitoring.compose.yml up -d --pull never --no-build --force-recreate node-exporter grafana
   ```
   Skipping this step leaves the backup alerts blind. Once backups are enabled,
   missing data alerts too (see below), so skipping it is not silent.
6. **First run and first check:**
   ```bash
   sudo systemctl start restic-backups-lab.service && sudo journalctl -fu restic-backups-lab.service
   sudo systemctl start restic-check.service && sudo journalctl -u restic-check.service -n 20 --no-pager
   ```
   The first run uploads everything and can take a while.

Two Grafana alerts exist: **Backup job failed** (the backup or check unit is in
the failed state for 5 minutes) and **No backup run for 36 hours** (the timer
stopped firing). While backups are disabled the series do not exist and missing
data is treated as OK; once `bandit-lab.backups.enable = true`, missing data
alerts instead, so a node-exporter that was not recreated cannot hide a failure.
Expect the "no backup run" alert from enabling until the first scheduled 04:30
run (the timer has not fired yet, and a manual `systemctl start` does not count).
A backup or check that hangs is stopped by a timeout (12 h and 6 h) and so
shows up as a failed unit; the weekly check waits up to 2 h for a running
backup's repository lock instead of failing.

### Restore drill (do this once, then yearly)

CX-2 provides `tools/restore-drill.sh lab|laptop [snapshot-id]` for the peer
backups. **Run as the owner on the source host**: `lab` on bandit-lab restores
its snapshot from the laptop; `laptop` on bandit restores its snapshot from the
lab. The installed `restic-peer` wrapper supplies credentials; the script never
decrypts SOPS or prints them. It resolves exactly one host-matching snapshot,
restores by full ID into fresh private scratch space and uses restic `--verify`
to check restored content. `--no-cache --no-lock` avoids repository/cache writes;
do not run the drill during peer pruning, which could remove the chosen snapshot.

The lab drill checks Vaultwarden/Mrija SQLite integrity and nonempty schemas,
records the Vaultwarden user count, imports the MySQL and PostgreSQL dumps,
requires application tables/databases, and boots the restored Minecraft world.
It restores Ghost `content-data` too and verifies the restored files with restic.
The laptop drill restores and verifies `Documents`, requiring at least one file.
These are bounded recovery samples, not a complete application or home recovery.

All Docker names start `restore-drill-`; SQL containers use network `none` and
tmpfs database directories. The Minecraft container mounts only the scratch
copy and uses the default bridge for Paper's excluded download cache, with no
published ports. **Restored plugins are disabled** because they can contain
external-service credentials; plugin integrations are not tested. No live
container, production volume or service is restarted or mounted. Images must
already be loaded (`--pull never`); the drill leaves the image cache unchanged.
Exit/INT/TERM traps remove the exact temporary containers (including any
anonymous image volumes) and scratch tree. Cleanup failure reports the exact
names/path and retains scratch for the owner. SIGKILL or a reboot cannot run a
trap; inspect `docker ps -a --filter name=restore-drill-` and the corresponding
scratch paths before removing only those resources.

Owner prerequisites: Docker access, `restic-peer`, Python 3 with SQLite, Bash,
gzip, coreutils, findutils and grep. Budget free scratch disk for the restore;
SQL containers each have a 2 GiB memory cap and Minecraft has 4 GiB. Larger
databases may require a reviewed resource-limit change. Load the MySQL 8.4 and
Minecraft image digests used by their owning modules (also pinned in the
script), plus PostgreSQL 16, matching the lab's native PostgreSQL major version.
Pin the PostgreSQL image by its inspected digest:

```bash
# Owner on the lab, one-time drill image preparation:
sudo docker pull postgres:16
pg_ref=$(sudo docker image inspect postgres:16 --format '{{index .RepoDigests 0}}')
sudo env PG_IMAGE="postgres:16@${pg_ref#*@}" bash tools/restore-drill.sh lab

# Owner on the laptop (no Docker needed for this sample):
sudo bash tools/restore-drill.sh laptop

# Offline fixture checks, no credentials or Docker daemon used:
python3 ci/test-restore-drill.py
```

Record UTC date, full snapshot IDs, image digests, output counts and each PASS
line after **both** owner runs. Do not publish database contents or private
diagnostics. As of 2026-10-10: source, shell syntax, ShellCheck and isolated
fixtures checked; **no actual peer snapshot or live Docker restore has been
tested by Codex**. The owner-run result is pending; this does not close goal #1.

For the optional B2 repository, the older manual smoke checks below remain
available. They do not establish SQL import or Minecraft startup acceptance.

Never restore over live data to test. The module installs a wrapper, `restic-lab`,
that already knows the repository, password file and B2 credentials (plain
`restic` is not on the PATH). Restore into a scratch directory:

```bash
sudo restic-lab snapshots
sudo mkdir /root/restore-test
sudo restic-lab restore latest --target /root/restore-test --include /var/backup
sudo restic-lab restore latest --target /root/restore-test --include /srv/containers/aiia/content-data
```

Restoring only what you check keeps the drill small (do not restore the whole
maildir just to test). restic keeps absolute paths, so the files appear under
`/root/restore-test/var/backup/restic-staging/` and `/root/restore-test/srv/...`.
Verify each dataset:

- Vaultwarden: `sudo sqlite3 /root/restore-test/var/backup/restic-staging/vaultwarden/db.sqlite3 'PRAGMA integrity_check; SELECT count(*) FROM users;'` prints `ok` and a plausible count.
- AiiA database: `zcat /root/restore-test/var/backup/restic-staging/aiia/mysql.sql.gz | head -20` shows a valid dump header, and `zcat ... | grep -c 'CREATE TABLE'` is not zero.
- PostgreSQL: `zcat /root/restore-test/var/backup/postgresql/all.sql.gz | head`.
- Files: spot-check a Ghost content directory and the Mrija data against the live ones.

When satisfied: `sudo rm -rf /root/restore-test` and note the date of the
successful drill here.

### Real recovery (per dataset)

Keep the old data (rename it) before putting anything back, stop the affected
container first, and start it again afterwards.

- **Vaultwarden:** the data comes from `restic-staging/vaultwarden/` (not from
  `/srv/...`): restore that directory's contents into
  `/srv/containers/vaultwarden/data/`, then start the container.
- **AiiA database (SQL dump, must be imported, not copied):** with the MySQL
  container running and empty:
  `zcat .../aiia/mysql.sql.gz | docker exec -i aiia-mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot'`.
  Ghost content comes back as plain files under `/srv/containers/aiia/content-*`.
- **PostgreSQL (SQL dump):** `zcat .../postgresql/all.sql.gz | sudo -u postgres psql`.
- **Mrija archive:** restore `maildir/` and the `data/` files; the SQLite index is
  `restic-staging/mrija/mail_index.sqlite`.

Not recoverable from this backup: the Wazuh indexer data and agent keys (agents
must be enrolled again), Grafana and Prometheus history, and the lab's own sops
age key (`/var/lib/sops-nix/key.txt`). For a lost disk you need your own sops age
key to decrypt `secrets/lab.yaml` (it holds the repository password and the B2
key); re-provision a lab key and re-key `.sops.yaml` afterwards
(`sops-split.md`).

### Accepted residual risks

- The B2 application key on the lab must be able to delete (restic prunes), so a
  fully compromised lab can destroy the backups. Real protection needs a second,
  prune-only key used from another machine or an append-only target; a "keep
  prior versions" lifecycle rule alone does not help because restic deletes all
  versions, and Object Lock conflicts with restic's own lock files. Left as a
  separate decision.
- The repository password and B2 key live on the lab, protecting data the lab
  already holds; the offline copy of the password is mandatory.
- One failing dataset (for example the MySQL container being down) fails the
  whole run, loudly, rather than skipping it silently. A catch-up run at boot
  can fail once if it starts before MySQL is ready. restic exit code 3 (a file
  vanished mid-run) also raises the failed alert.

## Current status

The above tests remain pending explicit maintenance approval. Existing backup
paths, timestamps, checksums, and integrity results are recorded in
[`services.md`](../services.md).
