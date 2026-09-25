# Minecraft administration

Verified live on 2026-09-22 after activation. Existing server and worlds preserved.

## Server and backup

- Paper 26.2 build 127 (`ad9a034`); Temurin Java 25.0.4+7-LTS.
- Host: bandit-lab; service: `docker-minecraft.service`; container: `minecraft`.
- Data: `/srv/containers/minecraft/data` (container `/data`); plugins: `data/plugins`.
- Declarative configuration: `hosts/bandit-lab/services/minecraft/default.nix`; staging: `minecraft-plugins.service`.
- Online mode enabled; whitelist disabled; existing ports/gameplay/world configuration preserved.
- Live baseline: `allow-flight=true` and ViaVersion's
  `packet-limiter.enabled=false`. The declarative staging service targets only those
  exact persistent fields; it does not use broad `OVERRIDE_SERVER_PROPERTIES` rewrites.
  Unexpected or missing target sections fail the service before plugin staging.
- ViaVersion's packet limiter is disabled (`enabled: false`) because Paper's existing
  packet limiter remains the authoritative protection layer; ViaVersion's
  `packet-size-limiter` is unchanged. Paper packet-limiter settings are unchanged.
  `allow-flight=true` only prevents false flying checks during lag or unusual movement;
  it does not grant creative flight on this survival server.
- CommandPanels and SModeration Phase 3 changes are live; the container is running with
  seven plugins, zero restarts, no startup ERROR/Exception, and health passed.
- SModeration live state: `force-reason=true`, all seven feature keys remain `true`,
  and custom `Warn` is registered as `smod.warn`.
- Pre-update backup: `/srv/containers/minecraft/backups/plugin-update-20260922-062200/data.tar.gz`;
  SHA256 `5fe664db499e143565b284136bcda9a8a9127a091f09443b839973bd0409abe1`.
- Cold backup after `save-all flush` and graceful stop:
  `/srv/containers/minecraft/backups/admin-20260921-163140/data.tar.gz`.
- Archive listing verified; SHA256:
  `14cdd51311b032fffe2480f8646af801583e228e9cb879e93084d1428be49df3`.
- Backup contains the entire data directory, including worlds, plugins, properties, operators and whitelist.
- `AxGraves-config-before.yml` in that backup directory preserves the generated config before tuning.

## Plugins

| Plugin | Version | Official source | Result |
| --- | --- | --- | --- |
| LuckPerms | 5.5.71 | https://modrinth.com/plugin/luckperms | Enabled |
| SModeration | 2.0.0 | https://modrinth.com/plugin/smoderation | Enabled, 12 commands registered |
| InventoryRollbackPlus | 1.8.4 | https://modrinth.com/plugin/inventoryrollbackplus | Enabled, 5 startup tests passed |
| AxGraves | 1.32.0 | https://modrinth.com/plugin/axgraves | Enabled |
| ViaVersion | 5.12.0 | https://hangar.papermc.io/ViaVersion/ViaVersion | Live |
| ViaBackwards | 5.12.0 | https://hangar.papermc.io/ViaVersion/ViaBackwards | Live |
| CommandPanels | 4.2.4 | https://github.com/rockyhawk64/CommandPanels/releases/tag/4.2.4 | Live |
| PlaceholderAPI | 2.12.3 + Player expansion | https://hangar.papermc.io/HelpChat/PlaceholderAPI | Enabled and verified live |

The managed plugin releases are pinned with exact download URLs and hashes in the
Nix module; the Modrinth-hosted releases explicitly list 26.2 compatibility, while
CommandPanels 4.2.4 is pinned from its official GitHub release.
Paper's bundled spark remains available. No client mods or EssentialsX installed.
CoreProtect is deferred: public CE 24.0 release notes explicitly mention 26.1,
but 26.2 support is currently a development/supporter build rather than a verified
public release:
https://github.com/PlayPro/CoreProtect/releases.

## Administrator

Administrator: `fancy8869`, UUID `623c7ee4-71ca-487a-b92a-a4564e43fbb9`.
Level-4 OP and LuckPerms `admin` membership verified live.
The mistakenly requested Ted account has been de-opped and removed from `admin`.
Before this correction, operators were backed up to
`data/ops-before-admin-correction-20260921-1926.json` and LuckPerms exported to
`data/plugins/LuckPerms/before-admin-correction-20260921-1926.json.gz`.
The admin-phase LuckPerms export is
`/data/plugins/LuckPerms/before-admin-phase3-20260922.json.gz`.

`admin` has `luckperms.*`, `inventoryrollbackplus.*` and these documented nodes:

```text
smod.menu smod.mute smod.preventmute smod.ban smod.preventban
smod.kick smod.preventkick smod.notifications smod.unmute smod.unban
smod.logs smod.invsee smod.invsee.modify smod.invsee.preventmodify smod.offlinetp smod.warn
smod.enderchestsee smod.enderchestsee.modify smod.vanish
smod.vanish.see smod.socialspy bandit.admin.menu
commandpanels.command.reload commandpanels.command.generate commandpanels.command.data
commandpanels.command.open commandpanels.command.open.other
```

No global `*` granted. Vanilla administration/teleport commands remain available
through OP. SModeration permission reference:
https://github.com/Shiewk/SModeration/blob/main/docs/permissions.md.
Prefix metadata is `[Admin]` (priority 100); displaying it in chat needs a chat
formatter, which was not installed solely for cosmetics.

The admin panel gate is `bandit.admin.menu`; it is granted to the intended
administrator. Panel actions remain player-executed and use the existing native
SModeration, teleport, inventory, and InventoryRollbackPlus permissions. The untimed
native `Warn` custom punishment is registered as `smod.warn`; `/modlogs <player> all`
shows the player's moderation history. `fancy8869` passes the menu permission checks;
`Kirafunk` has no `bandit.admin.menu` grant.

Whitelist entries verified live: `CringeLord21`, `Kirafunk`.

## In-game commands

The warning command and permission-placeholder fix are live. The panel commands
are registered:

```text
/admin
/admin <player>
/warn <player> <reason>
/modlogs <player> all
/offlinetp <player>
```

Existing commands:

```text
/plugins
/lp user fancy8869 info
/lp editor
/smod
/modlogs <player>
/invsee <player> inventory
/invsee <player> equipment
/enderchestsee <player>
/vanish
/vanish list
/mute <player> <duration> <reason>
/unmute <player>
/ban <player> <duration> <reason>
/unban <player>
/kick <player> <reason>
/irp help
/irp forcebackup player fancy8869
/irp restore fancy8869
```

Daily admin workflow: use `/admin` for server tools, `/admin <player>` for inspection
and a force backup, then `/modlogs <player> all` before any moderation action. The
panel intentionally has no restore, punishment buttons, console actions, permission
grants, or server controls.

CommandPanels is the `/admin` frontend; `/smod` remains the SModeration backend.
PlaceholderAPI 2.12.3 plus its Player expansion resolve the `%player_name%`
permission condition that gates the panels.

InventoryRollbackPlus passed 5/5 live tests. Inventory restoration can overwrite
the current inventory: force a fresh backup first, then inspect the desired snapshot
in the restore GUI. No real inventory
was restored during setup. Old losses are recoverable only if a suitable backup
exists. IRP now has six join and six quit snapshots for fancy8869; death snapshots
and the restore GUI still need a harmless dedicated test. Defaults retain 10 join,
10 quit, 50 death, 10 world-change and 10 forced backups per player.

AxGraves stores items and XP, saves graves with a 30-second autosave interval,
and now retains graves for 86400 seconds (24 hours). Only the owner can interact
or instantly collect. Expired graves drop their contents; this is not indefinite
storage. Existing keep-inventory behavior is not overridden. IRP retains its
early death snapshot setting (`allow-other-plugins-edit-death-inventory: false`).

Once CoreProtect compatibility is verified and it is installed, configure normal
block/container logging and grant its documented inspect/lookup/rollback/restore
nodes. These commands are **not available yet**:

```text
/co inspect
/co lookup u:<player> t:1h r:10
/co rollback u:<player> t:1h r:10
/co restore u:<player> t:1h r:10
```

Rollback/restore examples are destructive actions, not setup tests.

## Future moderator (no OP)

Run as administrator, substituting the intended account for `<player>`:

```text
/lp creategroup moderator
/lp group moderator permission set smod.menu true
/lp group moderator permission set smod.kick true
/lp group moderator permission set smod.mute true
/lp group moderator permission set smod.unmute true
/lp group moderator permission set smod.logs true
/lp user <player> parent add moderator
```

Do not grant this group OP, admin inheritance, LuckPerms administration, inventory
modification or rollback rights. Add other specific permissions only when needed.

## Operations and continuation

## Offline trade-rebalance maintenance

`hosts/bandit-lab/services/minecraft/disable-trade-rebalance.pl` is not run by
`minecraft-plugins.service`. Use it only as an explicit, offline maintenance
operation after all gates below pass:

1. **BACKUP:** make and verify a full consistent backup of
   `/srv/containers/minecraft/data`, including the target world's
   `level.dat`; record its checksum and restore location.
2. **STOP:** stop/quiesce `docker-minecraft.service`; do not edit a live world.
3. **COPY:** copy the target `level.dat` into an isolated working directory and
   verify that the copy is owned by the operator and not writable by Paper.
4. **TEST/RESTORE:** run the unchanged script only on that copy, inspect its
   output, validate the result, and retain the original until a restore test is
   complete. Restore the original on any error or unexpected result.
5. **OWNERSHIP:** before any approved replacement, verify the destination
   ownership is the Paper container's `1000:1000` and mode is appropriate for
   the existing data directory.
6. **GO:** obtain an explicit maintenance GO after backup, offline state,
   isolated-copy result, and restore path are all recorded. A source change or
   Nix staging run is not a GO.

This procedure does not authorize deployment, restart, or live-world mutation;
those require a separate maintenance action.

Console (SSH as vino; no public RCON):

```sh
docker exec --user 1000 minecraft mc-send-to-console 'plugins'
docker exec --user 1000 minecraft mc-send-to-console 'save-all flush'
docker logs --since 5m minecraft
# Restart only after confirming the server is empty: mc-send-to-console 'list'
sudo systemctl restart docker-minecraft.service
bandit-lab-health
```

Treat restarts as maintenance actions: announce the interruption, confirm
zero online players with `list`, then save and restart. Never restart during
active gameplay merely to perform a routine verification.

Before any future modification, take a full consistent backup manually; automated
Nix staging does not create backups. Never extract an old world backup over a running
server. Restart verification: all seven plugins enabled, three worlds loaded, ready
at 06:26:52, no new startup ERROR/stack trace; this activation also passed health checks.
OP, admin membership, inventory-edit permission and prefix survived restart.
Generated plugin data, LuckPerms database, ops.json and the three AxGraves settings
are live runtime state; Nix stages jars without overwriting those configurations.

Remaining work:

- Log in as fancy8869 and test `/admin`, `/admin <player>`, `/smod`, inventory
  inspection, `/modlogs`, `/offlinetp`, and `/irp restore` navigation. Test `/warn`
  only with a consenting test account because it deliberately creates history.
  Use a disposable test inventory for death/grave retrieval and restoration tests.
- Verify a released CoreProtect artifact explicitly supporting 26.2 before installation.
- NVIDIA mismatch resolved: the running kernel module and userspace are both
  `595.99.02`; `nvidia-persistenced.service`, `nvidia-smi`, and
  `bandit-lab-health` all pass after the host maintenance. Systemd still logs a
  harmless warning because the generated unit references the legacy `/var/run`
  PID path; update that unit only if the warning needs cleanup.
- Broader Portainer/container/monitoring/firewall audit remains separate work.
