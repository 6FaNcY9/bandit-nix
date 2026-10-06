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

Not included on purpose: Portainer (retired; local rollback archive exists), the
Minecraft world, `/srv/storage` (Samba share), Grafana/Prometheus data and the
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
   alert rules changed in the same release; the running containers keep the old
   ones until they are recreated:
   ```bash
   sudo docker compose -p monitoring -f /etc/bandit-lab/monitoring.compose.yml up -d --pull never --no-build
   ```
6. **First run and first check:**
   ```bash
   sudo systemctl start restic-backups-lab.service && sudo journalctl -fu restic-backups-lab.service
   sudo systemctl start restic-check.service && sudo journalctl -u restic-check.service -n 20 --no-pager
   ```
   The first run uploads everything and can take a while.

Two Grafana alerts exist: **Backup job failed** (the backup or check unit is in
the failed state for 5 minutes) and **No backup run for 36 hours** (the timer
stopped firing). Both treat missing data as OK, so they stay quiet while backups
are disabled.

### Restore drill (do this once, then yearly)

Never restore over live data to test. Restore into a scratch directory:

```bash
sudo -i
export RESTIC_REPOSITORY="$(cat /run/secrets/restic-repository)"
export RESTIC_PASSWORD_FILE=/run/secrets/restic-password
set -a; . /run/secrets/rendered/restic-b2.env; set +a
restic snapshots
mkdir /root/restore-test && restic restore latest --target /root/restore-test
```

restic keeps absolute paths, so the files appear under
`/root/restore-test/var/backup/restic-staging/` and `/root/restore-test/srv/...`.
Verify each dataset:

- Vaultwarden: `sqlite3 /root/restore-test/var/backup/restic-staging/vaultwarden/db.sqlite3 'PRAGMA integrity_check; SELECT count(*) FROM users;'` prints `ok` and a plausible count.
- AiiA database: `zcat /root/restore-test/var/backup/restic-staging/aiia/mysql.sql.gz | head -20` shows a valid dump header; `zcat ... | grep -c 'CREATE TABLE'` is not zero.
- PostgreSQL: `zcat /root/restore-test/var/backup/postgresql/all.sql.gz | head`.
- Files: spot-check `maildir` and the Ghost content directories against the live ones.

When satisfied: `rm -rf /root/restore-test` and note the date of the successful
drill here. A real recovery is the same procedure, then stop the affected
container, move the restored data into place (keep the old directory), and start
it again. For a lost disk you additionally need your own sops age key to decrypt
`secrets/lab.yaml` (it holds the repository password and the B2 key); the lab's
own key in `/var/lib/sops-nix/key.txt` is not part of the backup.

## Current status

The above tests remain pending explicit maintenance approval. Existing backup
paths, timestamps, checksums, and integrity results are recorded in
[`services.md`](../services.md).
