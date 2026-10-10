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
- **B3 - build fetches its material. Done 2026-10-10** (live: 9 cobblestone from the chest, pad placed in 3 s, chest 9 -> 0; details in BOTS.md "Building"). Before placing, the job withdraws the blueprint's material list from the supply chest (keeper stock already knows the counts) and reports what is short. *Ships:* the same platform built by a bot that starts empty.
- **B4 - the builder gathers what is still missing. Done 2026-10-10** (live: bot6 with no cobblestone and no chest mined 9 stone inside the build and placed the pad in 23 s; cobblestone and dirt by mining, stone by mining and smelting; smelt path not yet live; details in BOTS.md "Building"). After the chest, the building bot mines the rest itself. *Ships:* "build this" from an empty chest ends with gathered material placed.
- **B5 - real base parts** (superseded by R4 below). Raise limits for a first useful structure (a MidariBread farm module): layer claims across several bots, simple scaffolding, `.schem`/`.litematic` import and map preview (Stage 5). *Ships:* one farm built from gathered materials.

Skip for this path: drag-box orders, roles, cave layer, precision tricks (Stages 1, 4, 6). Useful, not on the critical path.

## 3a. Bots: after B4, toward a base they build and run themselves

Owner's goal (2026-10-10): the bots follow one plan without help, build a base first (their respawn
point and a storage), and fill it with what is not farmed yet, iron and gold first. Estimate: about
**35-40 % there**. Gathering, ore heights, tools up to stone, claims, keeper and small builds exist.
A big build, a spawn point, storage and the plan itself do not. Sizes are in work sessions and are
**guesses**: about 20-30 sessions in all, 3-6 weeks at the pace of 2026-10-08..10. "Without
errors" is not reachable; the target is that the bots recover by themselves and need the owner
at most once a day.

| # | Stage | Done when | Size | Depends on |
| --- | --- | --- | --- | --- |
| R1 | Iron and gold quotas | Keeper plans for `raw_iron` and `raw_gold` (mine at the ore band, deposit into their chest); iron and gold arrive in the chest without help | 1-2 | B4 |
| R2 | Tool progression | A bot with iron in reach makes an iron pickaxe (gold needs it), sword and armour by itself, and the keeper keeps spare iron kits in the supply chest | 1-2 | R1 |
| R3 | Survival (Stage 3) | Arrow side-step, no swimming in lava, retreat at night, collect drops after a death; one day of shifts without a lost kit | 2-4 | R2 |
| R4 | Bigger builds | Blueprints larger than 5x5x3, block states (chest, furnace, bed facing; torch), reach from inside a structure or simple scaffolding, several builders on one blueprint; `base-v1.json` builds | 4-8 | B4; design reviewed by `architect` first |
| R5 | Respawn point | Each bot clicks the base bed once (and again after the bed is replaced); deaths respawn at the base | 1 (beds from the owner) / 2 (sheep for wool) | R4 |
| | | *Jobs `hunt` (sheep etc., shears first) and `bed` (craft, place, click, "spawn set at") and the agent commands `!huntAnimals`/`!placeBed` shipped 2026-10-10, live-tested on the stage incl. respawn at the bed. Left: the crew's beds in the lab's storage room (the foreman orders them), a night sleep run.* | |
| R6 | Storage | Deposits go to the chest that holds that item (`storage` roles in `base-v1.json`); the dashboard answers "where is X" | 2-3 | R4 |
| R7 | The plan | One ordered list (build base-v1 -> storage roles -> iron/gold quotas -> ...) that the hub works through, giving roles to bots and showing progress on the dashboard | 3-5 | R1, R4, R6 |
| R8 | Soak | Several days unattended; every failure fixed or turned into a self-recovery | 1-2 weeks alongside | R7 |

Blueprints: `hosts/bandit-lab/services/mcbots/blueprints/` (README there). `base-v1-shell-01..08`
can be built today (168 cobblestone, simulated, not yet live). The full `base-v1` with chests,
bed and furnace waits for R4.

Shortcuts that save the most: the owner provides beds and a starting kit (skips wool and R5's
sheep); the base is a blueprint the owner chooses, not one the bots design; R1-R2 before R4,
because they pay off at once.

## 3b. Hybrid bots: an LLM brain on top of the scripted bots (decided 2026-10-10)

The Andy-4.2 agents (`tools/mcagents/`, live 2026-10-10) split work by role, talk to each other
and recover from missing material; the scripted bots alone do not. They are **not a replacement**
for the mcbots code. They are a brain on top of it: the model chooses the next job, and walking,
digging, fighting, building, claims and protected areas stay the existing code. The rule is to
**think rarely and coarsely, script long and cheaply**:

- **Body (unchanged):** every bot is an mcbots bot.
- **Routines (scripted, no LLM):** long jobs that run for minutes to hours: `shift`, `guard`,
  AFK, keeper standing orders, `build`, crafting chains. Bots in a pure routine role (bot4 AFK at
  the gold farm, keeper workers) get no agent at all.
- **Brain (LLM, event-driven):** asked only when something happens: a routine ended or failed, a
  death, a message from a bot or player, or a 10-minute check-in. One brain can lead several
  scripted workers ("foreman").

Measured: about 1 s per decision with reasoning off, about 5.6 GB VRAM for the model. At one
decision per bot every 3 minutes, 20 bots use about 10 % of the GPU. **The limit is CPU, not the
GPU:** all lab bots run in one Node process, which used a full core (101 %) with 4 bots on the
lab (H6 profile on the laptop: 0.5-0.6 core, pathfinder block lookups were the top cost, cut by 18 %
with `pathcache.js`). The mcbots Docker network (`/29`) does not limit the bot count, because all
bots share the container's one address (BOTS.md fixed in H6).

| # | Step | Done when | Size | Owner |
| --- | --- | --- | --- | --- |
| H1 | Routines as LLM commands (**done 2026-10-10**, live: bot11 `!startShift`, bot12 `!guardHere`, no re-prompt in 165 s) | The translator offers `!startShift`, `!guardHere`, `!afkHere` and treats a running routine as busy (no re-prompting) | S | Claude |
| H2 | Event-driven brain plus GPU budget (**done 2026-10-10**, live 29 min instead of 1 h: 26 model calls for 4 agents, 1.05 s each, GPU 0.7 % average) | Prompts only on events or a 10-min check-in, a global cap on decisions per minute, decisions per hour in the log; a 1-hour run with 4 agents stays under 5 % GPU on average | S-M | Claude |
| H3 | Mixed teams (**done 2026-10-10**, docs only: the agent already ignores bots outside `AGENTS`; live in the H1 run: bot14 had no agent and never got a job while bot11-bot13 worked) | Bots not listed in `AGENTS` stay scripted; documented roles: bot4 AFK, the rest LLM-led | S | Claude |
| H4 | Foreman (**done 2026-10-10**: live with bot11 + workers bot12-bot14, the three were assigned within ~1 min and a shift collected 778 cobblestone / 196 logs in 13 min) | `!assign("bot2", "!collectBlocks(\"iron_ore\", 32)")` lets one brain run scripted workers; live with 1 brain + 3 workers | M | Claude |
| H5 | Run on the lab, not the laptop (**done 2026-10-10**: Ollama 0.34.2 GPU container with andy-4.2, `mcagents` systemd service with a scoped dashboard bearer, decisions on the dashboard; then lead mode: bot1 plans, bot2-bot4 and bot16-bot18 in a worker process work) | Ollama as a NixOS service (CUDA, loopback only, scoped unfree predicate); mcagents as a hardened systemd service; the agent authenticates to the dashboard with its own token (design reviewed first, see below) | M | Codex (Nix), Claude (token in mcbots) |
| H6 | More bots per lab (**done 2026-10-10**: profiled, pathfinder block lookups cached, `/29` claim corrected) | The CPU hog is found and fixed (profile first: view renderer, pathfinder, physics), then more bots through the existing hub/worker processes; the `/29` claim checked | M | Claude |
| H7 | Base from the agents | The four agents build `base-v1-shell-01..08` from gathered cobblestone on a flat 7x7 spot the owner picks | M | Claude, after H1-H2 |

H5 needs a design decision before code: the dashboard trusts the `Tailscale-User-Login` header,
so a host service must not reach it by faking that header. Options: (a) an agent token on the
dashboard, like the worker token; (b) the brain inside the mcbots process, with Ollama reachable
from the container on a dedicated network. Recommendation: (a). The `architect` subagent or
Codex reviews it before H5 starts.

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
