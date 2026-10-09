# Minecraft panel migration: maintenance runbook (historical)

> **Historical (2026-10-10):** the change described here is deployed: it has been on `main`
> since `40a947e` (2026-10-06) and `lab-update-apply.timer` applies `main`. The text below is
> the plan as written before activation; whether steps 1-4 were run is not recorded.

Nothing here has been run on production. Prepared 2026-10-06 on branch `main`, working
tree only (no commit, no push, no activation). A push to the watched branch can trigger
server activation, and `lab-update apply` is the only deploy path
([bandit-lab-updates.md](../bandit-lab-updates.md); the hourly timer is paused today).
**Merging or pushing this change is not the GO; running step 5 is.**

## What changes, and what does not

The data directory is **not** moved, converted or re-imported. The same itzg container
and image digest keep supervising the same `/srv/containers/minecraft/data`, so worlds,
dimensions, player identities (online-mode UUIDs), possessions and plugin data stay
where they are. Because there is no second supervisor, there is no takeover and no
port-25565 hand-over. "Import all data separately, retain the original" is satisfied by
a verified cold backup **plus** an untouched `data.pre-migration-<ts>` copy kept next to
the live directory (step 3).

Changes at activation: container recreated with `PAPER_BUILD=130` (same build as today),
`MOTD` env removed (value stays in `server.properties`), two loopback ports, a 60 s stop
timeout, `Restart=always`; `minecraft-stage` installs VoxelDash and BlueMap, then runs
the one-time seed (existing plugin jars are left alone); new units
`minecraft-backup.{service,timer}` and `minecraft-panel-https.service`; the restic job
gains the Minecraft snapshot (still disabled until B2 secrets exist).

Downtime: one restart (about a minute) plus the cold backup time before it.

## Rehearsal already done (disposable, on a verified consistent copy)

Source: `/srv/containers/minecraft/backups/plugin-update-20260922-062200/data.tar.gz`
(cold backup taken after `save-all flush` and a graceful stop),
SHA256 `5fe664db499e143565b284136bcda9a8a9127a091f09443b839973bd0409abe1`
(recomputed on the lab and again after copying to the test machine: match; gzip/tar
listing readable). Extracted into a fresh directory, never over production.

| Step | Result |
| --- | --- |
| `minecraft-stage` on the copy (migration run) | VoxelDash 1.2.1 and BlueMap 5.28 installed; the 7 existing plugin jars left alone (`already installed, leaving it to the panel`), PlaceholderAPI seeded, stamp written |
| Second run, after simulating a panel update (renamed Via jar) and a panel removal (AxGraves) | both survive; nothing re-added or replaced |
| Boot with the final env (`PAPER_BUILD=130`, same image digest, 3 GiB heap on the test machine) | Paper `26.2-130-ver/26.2@a3d63e8`, Java 25.0.4+7, all 10 plugins enabled, `Done (12.8s)`, 0 ERROR lines; panel and map answered HTTP 200 on loopback |
| BlueMap | listed `world`, `world_nether`, `world_the_end` and began rendering them |
| Graceful stop | exit 143 after `All dimensions are saved` |
| SHA256 of every file under `world/players`, `world/dimensions`, `level.dat`, `world/data` before vs after boot | `players/` identical; every terrain `region/*.mca` identical; changed only server-maintained files (`raids.dat`, `weather.dat`, `world_clocks.dat`, `level_overrides.dat`, one entities region, `level.dat`) |
| Plugin data, ops, whitelist, bans | changed only `luckperms-h2-v2.mv.db`, AxGraves `data.json`, `usercache.json`, a LuckPerms translations status file (all normal runtime writes) |
| `minecraft-backup` against the **running** copy, three runs, `MC_KEEP=2` | log showed `Automatic saving is now disabled` → `Saved the game` → `Automatic saving is now enabled`; checksum `OK`; retention left 2 archives |
| `tools/minecraft-restore-test.sh` on such an archive | extracted to a new directory, booted: 3 dimensions (overworld 16, the_nether 4, the_end 4 region files), 9 player files, 10 plugins enabled, 0 errors |

Found and fixed during rehearsal (kept as regressions): `compgen` is missing from Nix's
minimal bash (the seed guard silently treated every jar as missing); the snapshot
script treated a failing `docker inspect` as "stopped" and would have copied a live
world (it now fails closed); `tailscale serve --bg` blocks forever when Serve is not
enabled on the tailnet (the unit now time-boxes each call and always succeeds).

What the rehearsal cannot prove: that real players' possessions are intact in-game (the
copy runs in online mode, nobody can join it), the systemd restart path on NixOS, and
the Tailscale HTTPS route. Step 6 covers the first two on the real server; the third
needs your admin-console change.

## Before the GO: you

1. Decide, in the module, the two seeded choices: BlueMap `accept-download: true`
   (Mojang client jar download) and whether `MidariBread` (level-4 op) is intended.
2. In the Tailscale admin console enable **Serve** and **HTTPS Certificates**
   (otherwise the panel is SSH-tunnel only; nothing breaks).
3. Optional but recommended: create the four B2 secrets and enable
   `bandit-lab.backups.enable` ([backup-restore.md](../backup-restore.md)) in a
   **separate** earlier deployment, then confirm one restic snapshot contains
   `minecraft/data/world/level.dat`. Without it the off-host copy in step 3 is manual.
4. Commit (signed), push, and confirm `sudo lab-update check` shows exactly this change.
   Pick a quiet time; tell players.

## GO checklist (on the lab, as `vino`; `D=/srv/containers/minecraft`)

```bash
D=/srv/containers/minecraft; TS=$(date +%Y%m%d-%H%M%S); echo $TS
```

**1. Announce and empty.**

```bash
docker exec --user 1000 minecraft mc-send-to-console 'say Maintenance in 5 minutes: please log out'
# later:
docker exec --user 1000 minecraft mc-send-to-console 'list'; docker logs --since 10s minecraft | tail -2
# proceed only at "There are 0 of a max of 12 players online"
```

**2. Flush and stop (graceful).**

```bash
docker exec --user 1000 minecraft mc-send-to-console 'save-all flush'
sudo systemctl stop docker-minecraft.service      # SIGTERM, up to 60 s
docker logs --tail 40 minecraft 2>&1 | grep 'All dimensions are saved'   # must print
docker ps -a --filter name=minecraft --format '{{.Names}} {{.Status}}'   # gone or Exited
```

If `All dimensions are saved` is missing, stop here and investigate; do not copy.

**3. Full cold backup, checksum, extraction test, off-host copy, retained original.**

```bash
sudo mkdir -p $D/backups/migration-$TS
sudo tar --use-compress-program='zstd -T4 -3' -cf $D/backups/migration-$TS/data.tar.zst -C $D data
( cd $D/backups/migration-$TS && sudo sha256sum data.tar.zst | sudo tee data.tar.zst.sha256 )
sudo tar --use-compress-program=unzstd -tf $D/backups/migration-$TS/data.tar.zst >/dev/null && echo listing-ok
# extraction + boot test in a NEW directory (read tools/minecraft-restore-test.sh first):
sudo tools/minecraft-restore-test.sh $D/backups/migration-$TS/data.tar.zst   # from the repo checkout
# off-host copy (laptop), then verify the digest there:
scp -r bandit-lab:$D/backups/migration-$TS ~/minecraft-migration-$TS   # run on the laptop
( cd ~/minecraft-migration-$TS && sha256sum -c data.tar.zst.sha256 )
# retained original, same filesystem, instantly usable:
sudo cp -a $D/data $D/data.pre-migration-$TS
# integrity baseline for the comparison in step 6:
( cd $D/data/world && sudo find players dimensions level.dat data -type f -print0 | sort -z | sudo xargs -0 sha256sum ) | sudo tee $D/backups/migration-$TS/world-baseline.sha256 | wc -l
```

Stop and fix on any failure; the server is still down and unchanged.

**4. Deploy** (this is the activation; use a detached unit so an SSH drop cannot
interrupt it):

```bash
sudo lab-update check
sudo systemctl start --no-block lab-update-apply.service
sudo journalctl -fu lab-update-apply        # builds, test-activates, health, switches
```

`lab-update apply` rolls back on a failed health gate. The Minecraft panel/map/HTTPS
probes are warnings only; the game server is gated by its unit.

**5. Verify the server.**

```bash
systemctl status docker-minecraft.service minecraft-plugins.service --no-pager | head -20
docker logs minecraft 2>&1 | grep -E 'Loading Paper|Running Java|Done \(|Enabling|ERROR|Exception' | head -30
docker exec --user 1000 minecraft mc-send-to-console 'plugins'; sleep 2; docker logs --since 5s minecraft | tail -3
curl -s -o /dev/null -w 'panel %{http_code}\n' http://127.0.0.1:7867/
curl -s -o /dev/null -w 'map %{http_code}\n' http://127.0.0.1:8100/
sudo bandit-lab-health
```

Expected: `Paper 26.2-130`, Java `25.0.4`, the eight production plugins plus VoxelDash and
BlueMap enabled, no ERROR, panel and map `200`, health passes.

**6. Verify data and possessions** (before opening to players):

```bash
sudo systemctl stop docker-minecraft.service   # cold again, for an exact comparison
( cd $D/data/world && sudo find players dimensions level.dat data -type f -print0 | sort -z | sudo xargs -0 sha256sum ) > /tmp/world-after.sha256
diff <(grep players/ $D/backups/migration-$TS/world-baseline.sha256 | sort) <(grep players/ /tmp/world-after.sha256 | sort) && echo PLAYERS-IDENTICAL
diff <(grep /region/ $D/backups/migration-$TS/world-baseline.sha256 | sort) <(grep /region/ /tmp/world-after.sha256 | sort) && echo REGIONS-IDENTICAL
sudo systemctl start docker-minecraft.service
```

Both lines must print. Then, in game as `fancy8869`: log in, check inventory/ender chest
look as before, visit the Nether and the End, open `/admin`, `/lp user fancy8869 info`,
`/modlogs`. A second real player should check their own inventory. Do not use real
accounts for destructive tests.

**7. Panel, map, backup.**

```text
In game (as operator):  /voxeldash password <a long password>
Browser: panel https://bandit-lab.tail7facc9.ts.net/  (or the SSH tunnel in PANEL.md)
```

Then `sudo systemctl restart minecraft-panel-https` if Serve was enabled after
activation, and run `sudo systemctl start minecraft-backup`. Check the new
`$D/backups/auto/minecraft-*.tar.zst`, its `.sha256`, and rehearse once more with
`tools/minecraft-restore-test.sh` on it. Panel state (`plugins/VoxelDash/voxeldash.db`)
is part of the data directory and therefore of every backup; Tailscale Serve state is
re-created by `minecraft-panel-https` from the repository.

Keep `data.pre-migration-<ts>` and `migration-<ts>` for at least two weeks of normal
play, then remove them yourself (they hold a full copy of the world; the lab has 2.4 TB
free).

## Abort and rollback

Rule: **anything that happens after players have played again must not be rolled back
by restoring old world files.** Roll back the configuration; restore files selectively.

| Situation | Action | Keeps new play? |
| --- | --- | --- |
| Verification fails before anyone has played (steps 5-6) | `sudo nixos-rebuild switch --rollback`, `bandit-lab-health`. Data was never replaced. If files were damaged: stop the unit and `sudo rsync -a --delete $D/data.pre-migration-$TS/ $D/data/` | nothing to lose yet |
| Panel/map misbehave, game fine | `sudo nixos-rebuild switch --rollback` (the old module stages its pinned jars again; VoxelDash/BlueMap jars stay in `plugins/` but have no published port; remove them by hand if wanted: `sudo rm $D/data/plugins/{VoxelDash,BlueMap}-*.jar`). The old module also reinstalls its pinned versions of the other plugins, replacing any version the panel updated (plugin data is kept) | yes |
| A plugin update or install breaks the server | stop; delete that plugin's jar (panel Files, or `sudo rm`); start. Restore only that plugin's folder from the latest archive if its data is damaged | yes |
| World or player corruption after play | `sudo systemctl stop docker-minecraft`; take a **new** cold backup of the damaged state first (`post-play-<ts>`); restore from the newest verified archive into a scratch directory with `tools/minecraft-restore-test.sh`-style extraction; copy back only the damaged parts (a region file, one `players/data/<uuid>.dat`), not the whole tree; start; verify | yes, except the damaged parts |
| Disaster (disk lost) | restic restore from B2 (needs the repository password, backup-restore.md) into a scratch path; verify with the drill; then place it | up to the last snapshot |

New data written since the migration lives in the same directory as everything else, so
the first move in every non-trivial case is a fresh verified cold backup of the *current*
state.

## Continuation note

Done: stack selection with evidence, Nix module, staging/seed rules, snapshot, backup
and restore tooling, `lab-minecraft` check, health probes, runbooks, rehearsal.
Not done, on purpose: commit, push, activation, any change on production.
Open decisions and blockers for you: (1) the GO and its time slot; (2) Tailscale Serve +
HTTPS Certificates in the admin console; (3) B2 secrets for the off-host copy;
(4) BlueMap `accept-download`; (5) `MidariBread` op level; (6) whether the panel's
missing update indicator and marker actions are acceptable (otherwise a different
product would be needed and none of the candidates met all requirements without
docker.sock or a takeover); (7) a 50-player claim needs a load test on the lab.
After the GO: update [ADMIN.md](ADMIN.md) facts that change (plugin ownership, Paper
build), record the verification outputs, and delete the retained copies on schedule.
