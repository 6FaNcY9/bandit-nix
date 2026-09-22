# Minecraft administration

Verified live on 2026-09-21 after a graceful restart. Existing server and worlds preserved.

## Server and backup

- Paper 26.2 build 127 (`ad9a034`); Temurin Java 25.0.4+7-LTS.
- Host: bandit-lab; service: `docker-minecraft.service`; container: `minecraft`.
- Data: `/srv/containers/minecraft/data` (container `/data`); plugins: `data/plugins`.
- Declarative configuration: `hosts/bandit-lab/minecraft.nix`; staging: `minecraft-plugins.service`.
- Online mode enabled; whitelist disabled; existing ports/gameplay/world configuration preserved.
- Phase 2 pending deployment: `minecraft-plugins.service` now validates and targets only
  `server.properties` `allow-flight=true`, and only the `packet-limiter.enabled` field
  in ViaVersion's persistent `plugins/ViaVersion/config.yml`. These are persistent
  runtime files, so the service is the declarative reconciliation point; no broad
  `OVERRIDE_SERVER_PROPERTIES` rewrite is used. Unexpected or missing target sections
  fail the service before plugin staging. Live values may therefore drift until the
  configuration is deployed.
- ViaVersion's packet limiter is disabled (`enabled: false`) because Paper's existing
  packet limiter remains the authoritative protection layer; ViaVersion's
  `packet-size-limiter` is unchanged. Paper packet-limiter settings are unchanged.
  `allow-flight=true` only prevents false flying checks during lag or unusual movement;
  it does not grant creative flight on this survival server.
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
| ViaVersion | 5.11.0 | https://hangar.papermc.io/ViaVersion/ViaVersion | Existing, untouched |
| ViaBackwards | 5.11.0 | https://hangar.papermc.io/ViaVersion/ViaBackwards | Existing, untouched |

The four new releases explicitly list 26.2 compatibility in Modrinth metadata;
their SHA512 hashes and exact download URLs are pinned in the Nix module.
Paper's bundled spark remains available. No client mods or EssentialsX installed.
CoreProtect is deferred: public CE 24.0 release notes explicitly mention 26.1,
but no explicitly 26.2-compatible release artifact was verified:
https://github.com/PlayPro/CoreProtect/releases.

## Administrator

Administrator: `fancy8869`, UUID `623c7ee4-71ca-487a-b92a-a4564e43fbb9`.
Level-4 OP and LuckPerms `admin` membership verified live.
The mistakenly requested Ted account has been de-opped and removed from `admin`.
Before this correction, operators were backed up to
`data/ops-before-admin-correction-20260921-1926.json` and LuckPerms exported to
`data/plugins/LuckPerms/before-admin-correction-20260921-1926.json.gz`.

`admin` has `luckperms.*`, `inventoryrollbackplus.*` and these documented nodes:

```text
smod.menu smod.mute smod.preventmute smod.ban smod.preventban
smod.kick smod.preventkick smod.notifications smod.unmute smod.unban
smod.logs smod.invsee smod.invsee.modify smod.invsee.preventmodify
smod.enderchestsee smod.enderchestsee.modify smod.vanish
smod.vanish.see smod.socialspy
```

No global `*` granted. Vanilla administration/teleport commands remain available
through OP. SModeration permission reference:
https://github.com/Shiewk/SModeration/blob/main/docs/permissions.md.
Prefix metadata is `[Admin]` (priority 100); displaying it in chat needs a chat
formatter, which was not installed solely for cosmetics.

## In-game commands

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

Inventory restoration can overwrite the current inventory: force a fresh backup
first, then inspect the desired snapshot in the restore GUI. No real inventory
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

Console (SSH as vino; no public RCON):

```sh
docker exec --user 1000 minecraft mc-send-to-console 'plugins'
docker exec --user 1000 minecraft mc-send-to-console 'save-all flush'
docker logs --since 5m minecraft
sudo systemctl restart docker-minecraft.service
bandit-lab-health
```

Before any future modification, repeat a full consistent backup. Never extract an
old world backup over a running server. Restart verification: all six plugins
enabled, three worlds loaded, ready at 19:04:51, no new startup ERROR/stack trace.
OP, admin membership, inventory-edit permission and prefix survived restart.
Generated plugin data, LuckPerms database, ops.json and the three AxGraves settings
are live runtime state; Nix stages jars without overwriting those configurations.
The new Nix configuration has not been activated during this session.

Remaining work:

- Log in as fancy8869 and test `/smod`, inventory inspection and `/irp restore` navigation.
  Use a disposable test inventory for death/grave retrieval and restoration tests.
- Verify a released CoreProtect artifact explicitly supporting 26.2 before installation.
- Schedule a host reboot: NVIDIA kernel module 595.91.07 differs from userspace
  595.99.02, causing `nvidia-persistenced.service` failure and NVML mismatch.
  Health passes with this non-critical warning. No reboot performed; after reboot
  verify `nvidia-smi`, daemon status and `bandit-lab-health` again.
- ViaVersion reports 5.12 available; existing 5.11.0 deliberately retained here.
- Broader Portainer/container/monitoring/firewall audit remains separate work.
