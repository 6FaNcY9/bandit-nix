# Next goals (2026-10-10)

Evidence is from `origin/main` at `74f15c4` unless a branch is named. Lines marked
**guess** are not established by the repo.

## 1. Where each area stands

| Area | State (evidence) | Unfinished / risky |
| --- | --- | --- |
| Laptop `bandit` | GRUB+EFI, no LUKS block in `hosts/bandit/hardware.nix`; `trusted-users = ["root"]`, MCP servers sandboxed, libvirt needs admin auth (SECURITY-PLAN). Peer backup to the lab (`nixos/backup-peer.nix`). Recent laptop work is small (Prism Launcher). | No disk encryption, boot chain undecided: **parked by the owner (2026-10-10), the laptop stays at home.** Prep work waits on branch `luks-prepare`. Pick it up again when the laptop starts travelling. |
| Lab services | 14 service modules imported in `hosts/bandit-lab/default.nix`; Portainer and Wazuh removed from config; signed fast-forward-only auto-deploy (`lab-update`, `ci/test-lab-update.py`); 10 flake checks incl. `lab-surface`, `local-privilege`, `sops-isolation`. | Backblaze job exists but `bandit-lab.backups.enable` is off (secrets missing). **No restore has ever been tested** (SECURITY-PLAN, `backup-restore.md`). No container sets `no-new-privileges` or a read-only root (`container-hardening.md`). |
| Security hardening | Phases 1-2, 5, D3-D7 done; attack surface cut to tailnet; sops split into per-host files. | LUKS and boot chain parked (see laptop). Legacy `secrets/secrets.yaml` + its `TEMPORARY` rule in `.sops.yaml` still present (`sops-split.md` step 4 not done). GitHub branch protection is a manual step; whether it is set is **unknown**. |
| Minecraft server | Paper 26.2 build 130 behind Velocity + BotGate, BlueMap, VoxelDash, `minecraft-backup` timer in `services/minecraft/default.nix`, restore drill script `tools/minecraft-restore-test.sh`. | Archive restore drill passed (PANEL.md matrix row 5); a restic-to-world restore has not. A `docker-minecraft` restart kicks players and orphans Jarvis NPCs, so server changes need a quiet window. |
| Bots (mcbots) | 55 of the 202 commits on `main` since 2026-09-10. Hub + laptop worker, block claims, dashboard with BlueMap terrain, markers (`places.js`), in-game view, settings, guard, shifts, keeper (standing orders), torches, ore bands, sealing, safe digging, jobs survive restarts, crit/sweep combat. 855-line `test.js`. | Keeper never live-tested on the lab (AUTOPILOT M4). Kits still get lost (P1). **No `build` job** (design only, BOTS.md). `bots.js` is 1292 lines and growing. `mcbots-soak` monitor exists only on `claude/autopilot`. |

## 2. Next 10 goals, ranked

| # | Goal | Why | Done when | Size | Depends on |
| --- | --- | --- | --- | --- | --- |
| 1 | Restore drill from the peer backup | A backup never restored is a hope. Covers Vaultwarden, DBs, Minecraft world. | One lab snapshot and one laptop snapshot restored into scratch dirs, Minecraft world booted by `minecraft-restore-test.sh`, result dated in `backup-restore.md`. | S | - |
| 2 | ~~Reconcile stale docs~~ **done 2026-10-10** | Agents act on docs; several gave the wrong state. | Section 4. | S | - |
| 3 | Finish sops split cleanup | Legacy file still readable by the laptop host key; `TEMPORARY` rule lingers. | `secrets/secrets.yaml` and its rule gone, `github.yaml` rotated, `sops-isolation` check updated. | S | both hosts verified on split files |
| 4 | Bots: live-test keeper + land soak monitor | Standing orders are the base of every later bot goal and were only unit-tested. | Keeper on at `KEEPER_SITE` for a soak run; `mcbots-soak` shipped; report shows quotas met, 0 lost kits. | S | - |
| 5 | Bots: no lost kits (Stage 3 core) | Unattended gathering/building is pointless if kits vanish (bot1 x2, bot2, bot4 lost). | Keeper stocks spare kits; a dead bot re-arms from the chest and walks back to its drops; one full day of shifts with no lost kit. | M | #4 |
| 6 | Bots: `build` job MVP (**done 2026-10-10**, live-tested with bot6) | First step to the owner's "bots build the base". | See milestone B2 below. | M | #4, #10 |
| 7 | Off-site copy (B2) | The laptop stays home, so both peer copies sit in one house: one fire, flood or theft takes everything. | 4 secrets added (`tools/add-backup-secrets.sh`), `backups.enable = true`, first snapshot listed, alert fires on a failed run. | S | #1 |
| 8 | Container hardening, first candidates | No container has `no-new-privileges`; one privileged (cAdvisor). | Flag added one container at a time with a health check each; `lab-surface` (or a new check) asserts it. | M | - |
| 9 | Confirm GitHub branch protection on `main` | A push to `main` deploys the lab within the hour; protection against force-push/deletion is a manual setting nobody has confirmed. | Ruleset active, the rejection test in `bandit-lab-updates.md` run, date noted there. | S | owner (GitHub UI) |
| 10 | Split `bots.js` before it grows further | 1292 lines; the build job, kit restock and projects all land there next. | Jobs, upkeep and claims in their own modules, `test.js` unchanged and green, no behaviour change. | M | before #6 |

## 3. Bots: shortest path to "they build our base from what they gathered"

Each milestone ships on its own through `tools/ship-claude`, with tests and a bot6/bot7 local-stage check.

- **B1 - stocked supply (exists, verify).** Keeper live on the lab at the site marker; quotas for logs, cobblestone, coal, torches met without help. *Ships:* goal #4.
- **B2 - `build` from inventory.** The design in BOTS.md as written: JSON blueprint, max 5x5x3 / 75 plain blocks, bottom-up order, claims shared with digging, no scaffolding, fail before placing when material is missing, `remove: true` undo. Pure-function tests first. *Ships:* a bot builds and removes a 3x3 cobblestone platform away from spawn.
- **B3 - build fetches its material.** Before placing, the job withdraws the blueprint's material list from the supply chest (keeper stock already knows the counts) and reports what is short. *Ships:* the same platform built by a bot that starts empty.
- **B4 - keeper fills the shortfall.** A build's shortage becomes a temporary keeper quota (logs/cobblestone already have chains; add planks/stone via the existing craft/smelt jobs). *Ships:* "build this" from an empty chest ends with gathered material placed. **This is the goal.**
- **B5 - real base parts.** Raise limits for a first useful structure (a MidariBread farm module): layer claims across several bots, simple scaffolding, `.schem`/`.litematic` import and map preview (Stage 5). *Ships:* one farm built from gathered materials.

Skip for this path: drag-box orders, roles, cave layer, precision tricks (Stages 1, 4, 6). Useful, not on the critical path.

## 4. Contradictions and stale content

Fixed 2026-10-10 (docs only): panel/BlueMap/VoxelDash shown as deployed in `PANEL.md`,
`MIGRATION.md` (now historical), `ADMIN.md`, `services.md`, `backup-restore.md`; PGP removal marked
done and laptop encryption parked in `SECURITY-PLAN.md`; retired containers marked in
`container-hardening.md`; markers and safe digging marked done in `CONTROL-CENTRE-GOAL.md` and
`AUTOPILOT-REPORT.md`; `BOTS.md` intro, jobs table (`shift`, `guard`, `craft`, `smelt`) and Limits
match the code.

Still open:

- `SUPPLY_CHEST` in `mcbots/default.nix` is the old spawn chest. A `supply` marker overrides it,
  but the fallback should match (config change, ship when convenient).
- Whether the GO steps of `MIGRATION.md` (cold backup, pre-migration copy) were run is unknown.
- Local checkout `~/src/bandit-nix` is behind `origin/main` and has an uncommitted `flake.lock`.
  Side branches with unshipped work: `luks-prepare` (parked), `claude/autopilot` (`mcbots-soak`),
  `adr-community-alternatives`, `docs-redaction`.
