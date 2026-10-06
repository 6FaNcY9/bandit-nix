# Minecraft browser administration: selection, access, daily use

Status 2026-10-06: **prepared and tested on disposable servers; not committed, not
deployed.** Production is untouched. Activation needs the maintenance GO described in
[MIGRATION.md](MIGRATION.md).

## Decision

**Keep the existing itzg container as the only supervisor of production. Add VoxelDash
(admin panel) and BlueMap (live map) as Paper plugins. Nix owns infrastructure, backups
and the HTTPS front. No second server manager, no docker.sock, no takeover of port
25565.**

| Part | Choice | Why |
| --- | --- | --- |
| Supervisor | existing `docker-minecraft.service` (itzg), `Restart=always`, 60 s graceful stop | already runs the world; adding Crafty/Pelican/MCSManager would add a second supervisor that must take over 25565 |
| Admin panel | VoxelDash 1.2.1 (MIT, Paper plugin, Modrinth plugin marketplace) | the only candidate that meets the in-panel plugin browser without docker.sock or a takeover |
| Live map | BlueMap 5.28 (MIT, Paper plugin) | renders all three dimensions of the production copy; player markers, dimension switching |
| Backups | Nix `minecraft-backup` (daily, local) + restic job (off-host, already in repo, disabled until B2 secrets exist) | the panel's own backups are not save-flushed and have no retention |
| HTTPS | `tailscale serve` (tailnet only) | no public listener, no certificate handling in the repo; needs one owner action (below) |

Smallest supported stack: two jars, one oneshot unit, two scripts. No custom software
was written; the staging and backup scripts are glue around itzg, rsync, tar and restic.

## Verified production baseline (read-only SSH, 2026-10-06)

| Claim | Observed |
| --- | --- |
| Paper | `26.2-130` (docs said build 127; itzg floats to the newest build on every start, so the module now pins `PAPER_BUILD=130`; pin effect verified: `PAPER_BUILD=129` downloads `paper-26.2-129.jar`) |
| Java | Temurin `25.0.4+7-LTS`, image `itzg/minecraft-server@sha256:769a826c…` (`java25`) |
| JVM flags | `-Xms8G -Xmx8G` plus the Aikar set (`UseG1GC`, `MaxGCPauseMillis=200`, `G1NewSizePercent=30`, `G1HeapRegionSize=8M`, `InitiatingHeapOccupancyPercent=15`, `AlwaysPreTouch`, `DisableExplicitGC`, …) |
| Data | `/srv/containers/minecraft/data` (968 MB), bind-mounted at `/data`, owner `1000:1000` inside the container |
| Limits | container `--memory=12g --cpus=4`, not privileged, one mount, no docker.sock |
| Server | `max-players=12`, `online-mode=true`, `white-list=false`, `enable-rcon=false`, port 25565 bound to the tailnet address only |
| Worlds | one `world` with three dimensions under `world/dimensions/minecraft/{overworld,the_nether,the_end}`; player data in `world/players/{data,advancements,stats}` |
| Players online during the check | 0 |
| Old restart policy | systemd `Restart=on-failure` (a clean `stop` was not restarted) |

Things the docs did not say: `ops.json` also lists `MidariBread` at level 4 (the docs
name only `fancy8869`); decide whether that is intended. The cold backup of 2026-09-22
carried ViaVersion/ViaBackwards 5.11.0 while production runs 5.12.0 (irrelevant to the
rehearsal, noted for accuracy).

## Candidate comparison

"Tested" means driven through the browser or API on a disposable Paper 26.2 server;
"docs/source" means upstream documentation or source only (not run here).

| Candidate | Licence, maturity (GitHub/GitLab API, 2026-10-06) | Privileges and fit | Result |
| --- | --- | --- | --- |
| **VoxelDash 1.2.1** (+BlueMap) | MIT; 249 stars; releases 2026-06 and 2026-07 | runs inside the server JVM, one loopback port, no host access | **chosen**; tested |
| Crafty Controller 4.11.0 (+OPanel) | GPL-3.0; 253 stars; release 2026-09-16 | runs the server as its own child process, so it replaces itzg and must own 25565; image ships Java 8-25; no docker.sock needed. Plugins are installed by hand (its FAQ describes manual downloads) | fails requirement 3 and replaces the supervisor; docs/source |
| OPanel 2.2.5 | GPL-3.0; 294 stars; release 2026-10-04 | plugin; loads on Paper 26.2.130 (jar is built for 26.1) | tested: plugins page lists/enables/disables/uploads only, saves page imports zips, one shared access key (locks out after repeated failures), map route hidden from the nav and blank; fails requirements 3 and 5 |
| Pelican panel v1.0.0-beta38 + Wings v1.0.0-beta29 | AGPL-3.0 / MIT; **beta**; PHP 8.4 panel | Wings builds its Docker client from the environment (`environment/docker.go`), so it needs Docker daemon access = the host docker.sock (or a dedicated second daemon). Replaces itzg. Best plugin browser of the alternatives (`minecraft-modrinth` 1.1.2: browse, install, update detection, uninstall) | **incompatible** with "no host docker.sock"; docs/source |
| MCSManager v10.19.0 | Apache-2.0; 4980 stars; release 2026-10-04 | Docker instance mode needs the Docker daemon; process mode runs servers directly. Its marketplace deploys server templates, not plugins | fails requirement 3; docs/source |
| Kubek 4.0.2 | GPL-3.0; 133 stars; release 2026-06-18 | has Modrinth browse and update badges, but its documented Docker setup mounts the host docker.sock | **incompatible**; docs/source |
| PufferPanel 3.0.9 | Apache-2.0; 1753 stars; release 2026-07-14 | not evaluated beyond metadata | not assessed |

Crafty + OPanel, the combination you started from, does not meet the requirements:
neither half has a plugin marketplace, and Crafty would replace the supervisor.

## Feature matrix (chosen stack)

Legend: **T** tested in the browser/API on a disposable server, **C** configured in Nix
and checked by `lab-minecraft` / evaluation (not runtime-tested on production),
**D** per upstream documentation only.

| # | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Live map, markers, all dimensions, switching | **Met** (map). BlueMap loaded `world`, `world_nether`, `world_the_end` from the restored production copy; marker shows the player's head; map menu switches dimension | T (headless Chromium, screenshot) |
| 1 | Player actions on the map marker | **Not met.** BlueMap markers show names only. Actions live on VoxelDash's separate Players page (right-click menu) | T |
| 2 | Player list, whitelist, kick/ban/unban | Met | T: online list, whitelist add (`WlTestUser`, server confirmed), ban with reason (kicked, banlist confirmed), unban |
| 2 | Teleport, game mode | Met: teleport dialog (coordinates / to player / world / spawn); game mode dropdown (`playerGameType` read back as `1`) | T |
| 2 | Inventory and ender chest | Met for **online** players (view, give, clear). Offline inventory, death rollback and moderation stay with the existing SModeration / InventoryRollbackPlus / AxGraves workflows ([ADMIN.md](ADMIN.md)) | T (dialog, give); offline D |
| 3 | Prism-like content browser | **Met** with one gap. Modrinth marketplace in the panel: search (`chunky` → 3 results), descriptions, download counts, version picker (release/beta, game versions), install (hot-loaded, jar tagged with its Modrinth id), remove, per-plugin config editor | T |
| 3 | Compatibility filtering | Partial: the store filters by `26.2` and `paper`, but Modrinth metadata is loose (WorldEdit offered versions tagged `1.21.4`). Treat the filter as advice; test a plugin on a copy first | T |
| 3 | Update check and one-click update | **Not met.** No update indicator exists in 1.2.1 (the docs claim one; the UI and API show none) and an installed plugin shows "Installed" with no reinstall. Update = open the plugin, **Delete** (config and data stay), install the newer version from the Store, restart. Verified with WorldEdit 7.4.4-beta-01 → 7.4.6-beta-02 | T |
| 4 | Server version selection / updates | **Not in the panel**, by design. `VERSION` and `PAPER_BUILD` are Nix values; procedure below | C, T (pin) |
| 4 | Settings, gamerules | Met: `server.properties` editor (categorised) and a searchable gamerule list applied to the running server | T (pages), D (apply) |
| 4 | Console, files, logs | Met: live console (`say` reached the server log), file manager, log view | T |
| 4 | Start/stop/restart | Partial: no start/restart buttons. **Stop** (console `stop` or a schedule) exits cleanly and `Restart=always` brings the server back, which is a restart. `systemctl stop docker-minecraft` keeps it down | T (stop), C (restart) |
| 4 | Graceful shutdown | Met: `docker stop` took 2 s and logged `All dimensions are saved`; stop timeout is 60 s | T |
| 4 | Autostart, crash recovery | Configured: `Restart=always`, 10 s delay, no start limit; unit is foreground `docker run`, so any exit restarts | C (generated unit inspected); not crash-tested on production |
| 4 | Resource metrics | Met: memory, CPU, TPS, entities, chunks, uptime; profiling page | T |
| 4 | Schedules | Met: hourly/daily/weekly; actions command, broadcast, backup, reload, stop. A broadcast schedule fired at its minute | T |
| 5 | Full backups, retention, download | Met by Nix: daily consistent archive + `.sha256`, newest 14 kept, listing test; panel backups remain available for ad-hoc use (download button) | T (script on a running server) |
| 5 | Tested restoration | Met: `tools/minecraft-restore-test.sh` restored an archive taken from a running server into a new directory and booted it: 3 dimensions, 9 player files, 10 plugins enabled, 0 errors. Production-copy rehearsal: [MIGRATION.md](MIGRATION.md) | T |
| 5 | Off-host replication | **Configured, blocked on you.** The restic job snapshots the world through the same save-flushing script. It is disabled until the four B2 secrets exist ([backup-restore.md](../backup-restore.md)) | C (`lab-backup` check) |
| 5 | Private HTTPS, auth, permissions | Configured: Tailscale Serve (never Funnel) on 443 (panel) and 8443 (map); per-user panel accounts with per-feature roles. **Serve is not enabled on this tailnet** (`tailscale serve` answered "Serve is not enabled on your tailnet"), so the route is not runtime-verified | C; T for roles |

Not claimed: **50 concurrent players.** No benchmark was run; the server stays at
`max-players=12`, 8 GiB heap, 4 CPUs. A 50-player claim needs a load test on the lab
itself (the test machine here is a laptop); do not raise `MAX_PLAYERS` without one.

## Panel roles are not LuckPerms

VoxelDash accounts are separate from Minecraft permissions: each panel user gets
None / Read-only / Full per feature (Files, Server Config, SSH, Backups, Console,
Players, Schedules, Worlds, Resources, Motd, Profiling, GameRules). The server enforces
this on every API call. Results with a panel user that has **no** OP and no LuckPerms
group (HTTP, disposable server):

| Panel role | Result |
| --- | --- |
| Players = Read-only | `players/online` 200; `op`, `kick`, `ban` all 403; backups 403; files 403 |
| Players = Full | `kick` 200, `ban` 200, **`op` 200** (the user de-opped an operator in the UI with one click) |
| Backups = Read-only | list 200 only |
| Backups = Full | reaches restore (a restore overwrites live files) |

Consequences, applied in this repository:

- **There is no safe moderator role in the panel.** Players = Full contains OP
  management and inventory editing; Console, Files, Resources and Backups = Full are
  each equivalent to full control of the server. Moderators keep using in-game
  SModeration under the LuckPerms `moderator` group ([ADMIN.md](ADMIN.md)), which has
  no OP and no restore rights.
- Give panel accounts to administrators only. A read-only observer account
  (Players = Read-only, nothing else) is safe.
- A panel account is created by `/voxeldash password <password>` run in game by an
  operator (the account takes the operator's name and becomes an admin), and further
  accounts by an admin under Settings → Users. No panel password is stored in this
  repository or in sops.

## Who writes what

| Thing | Single writer | Notes |
| --- | --- | --- |
| VoxelDash and BlueMap jars | Nix (`minecraft-stage`, every activation) | bump the pinned version and hash in `default.nix` |
| BlueMap `core.conf` | Nix only when the file does not exist; BlueMap/operator afterwards | seeds `accept-download: true` and `metrics: false` |
| `CommandPanels/panels/*.yml` | Nix (every activation) | edits made in the panel's file manager are reverted at the next activation |
| All other plugin jars and their versions | the panel (or an operator) after the one-time seed | the seed installs a pinned jar only when no jar with that name prefix exists, then writes `/srv/containers/minecraft/data/.nix-seed-v1`; Nix never deletes or overwrites them again |
| Plugin settings, `server.properties` keys without an env var (view distance, MOTD, difficulty, …), gamerules | the panel | the one-time seed applied the previous `allow-flight`, ViaVersion and SModeration settings |
| `server.properties` keys with an env var: `max-players`, ops (`OPS`) | Nix | itzg rewrites them on every start; a panel edit of `max-players` is reverted at the next restart (verified: `max-players` and `view-distance` reverted when they had env vars; `motd` survived without one). `MOTD` and the other former env vars are removed so the panel owns them |
| Paper build, Java, JVM flags, memory/CPU, ports, volumes | Nix (`default.nix`) | |
| Backups, schedules for backups, off-host copy | Nix | do not add backup schedules in the panel (no retention) |
| Panel accounts and roles | the panel (`plugins/VoxelDash/voxeldash.db`, inside the data directory and therefore in every backup) | |

## Access and daily use

Addresses (after the Tailscale prerequisite is done; tailnet only):

- Panel: `https://bandit-lab.tail7facc9.ts.net/`
- Map: `https://bandit-lab.tail7facc9.ts.net:8443/`

**One-time prerequisite (you):** in the Tailscale admin console enable Serve and
HTTPS Certificates for the tailnet (enabling HTTPS publishes machine names in public
certificate-transparency logs), then on the lab:
`sudo systemctl restart minecraft-panel-https`. Until then, and as a fallback, use an
SSH tunnel from the laptop:

```bash
ssh -L 7867:127.0.0.1:7867 -L 8100:127.0.0.1:8100 bandit-lab
# panel http://127.0.0.1:7867/   map http://127.0.0.1:8100/
```

Daily:

1. Players page → right-click a player: inventory, teleport, kick, ban/temp-ban, mute;
   game mode in the table; whitelist and bans in their tabs.
2. Plugins → Store: search, open a result, pick a version, Install; restart in a quiet
   moment (`list` first). Remove or update via the plugin's own page (Delete, then
   install the newer version). After installing or updating, check the console for
   errors; the store's compatibility filter is advisory.
3. Settings → Server / Game Rules for runtime settings; Schedules for broadcasts and
   commands. Console for one-off commands.
4. Before any risky change: `sudo systemctl start minecraft-backup`, then check the
   newest `/srv/containers/minecraft/backups/auto/minecraft-*.tar.zst` and its
   `.sha256`.

Server version change (Nix, maintenance window): take a backup, set `VERSION` and/or
`PAPER_BUILD` in `hosts/bandit-lab/services/minecraft/default.nix`, build, test the new
build on a restored copy with `tools/minecraft-restore-test.sh` plus the plugin list,
then deploy. A newer Minecraft version can make older world files unreadable by an
older server: the cold backup is the way back.

Browser side effects to know: the panel UI loads its code editor, avatars and item
icons from `cdn.jsdelivr.net`, `minotar.net`, `mc-heads.net` and `mcasset.cloud` in
**your browser**; the server only calls `api.modrinth.com` (store) and, for BlueMap,
`piston-data.mojang.com` / `piston-meta.mojang.com` (client jar for textures, after
`accept-download`). The BlueMap download is Mojang's client jar; the server already runs
under `EULA=TRUE`, but confirm you are happy with that seed before the GO.

## Modded instances (Fabric / Forge)

Paper plugins and datapacks are not Fabric/Forge mods; production stays on Paper.
VoxelDash also ships `fabric*`, `forge*` and `neoforge*` jars and its store lists
mods for those loaders, so a separate modded instance could be run later as its own
container with its own data directory, ports and `lab-surface` entries. That is
capability only: nothing modded was built or tested here, and CurseForge needs an API
key. OPanel also lists Fabric/Forge/NeoForge builds (not tested).

## Network exposure

Accepted risk: the panel can upload plugin jars, i.e. run code as uid 1000 inside the
container, which sits on Docker's default bridge with other containers. Tailscale Serve
also reaches every tailnet node your ACLs allow; only VoxelDash's own login stands
between them and the panel. Restrict the ACL to admin devices and keep panel accounts
to administrators. Check which containers share the bridge with
`docker network inspect bridge` before the GO.

`lab-surface` and `lab-minecraft` (flake checks) enforce: game port on the tailnet
address; panel (7867) and map (8100) on `127.0.0.1` only; RCON disabled and unpublished;
one mount (`/srv/containers/minecraft/data`), no `--privileged`, no `cap-add`, no
docker.sock; no firewall port opened for the panel. VoxelDash's built-in SSH/SFTP
server (Settings) is off by default and must stay off: it would listen inside the
container and is unpublished. Server Config also exposes RCON settings; enabling RCON
there changes nothing on the network (no published port) but keep it off.

## Evidence

Disposable rig (laptop, rootless Docker, the same pinned itzg image): servers on
`127.0.0.1` only, test players are offline-mode bots (`mineflayer` 26.1 client through
ViaBackwards), browser is headless Chromium. Panel feature results above are from that
rig; the production baseline is from read-only SSH. Test data: the fresh worlds of the
rig and a restored copy of
`plugin-update-20260922-062200/data.tar.gz` (SHA256 verified, see
[MIGRATION.md](MIGRATION.md)). Pinned artifacts (SHA256):

| Artifact | SHA256 |
| --- | --- |
| `voxeldash-spigot-1.2.1.jar` | `9b05184695b5b6117aceca6ed6b13b16f3f04584e3c4db592980f3182f2158b7` |
| `bluemap-5.28-paper.jar` | `4cfb4a9963132d5be0a9db031a28a98e9df92deed37ebb0756d3a7dd8721ab98` |
| `opanel-paper-26.1-build-2.2.5.jar` (evaluated, not deployed) | `f0f9eb3caaa2871e86b71087114fd24cbc0ee64b6ca44a84563586790ace0ed5` |
