# Minecraft bots (Mineflayer)

Mineflayer bots join Paper through Velocity and
BotGate and are controlled from a small web dashboard. Code:
`hosts/bandit-lab/services/mcbots/` (`app/` is the Node app, `default.nix` the
lab deployment). Crafting, smelting and small builds exist; schematic import does
not yet (see Building). Goals in stages: `CONTROL-CENTRE-GOAL.md`. A new job
type is one entry in `JOBS` and one in `VALIDATE` in `app/bots.js`.

## How it fits together

- Bots are named `bot1`..`bot4` on the lab (`bot5`+ on the laptop). BotGate
  admits offline logins only for `^bot[0-9]{1,2}$` from the owner laptop
  (`100.102.247.30/32`) or the `mcbots` Docker network (`10.250.77.0/29`).
- Lab: container `mcbots` (nix-built image, non-root uid 1000, 2 GiB / 2 CPUs,
  no capabilities, no mounts) on network `mcbots`, connecting to `velocity:25565`.
  The dashboard listens on `127.0.0.1:8095` (host) and is published to the
  tailnet by the oneshot `mcbots-https` (`tailscale serve`, never Funnel).
- Protocol: Mineflayer 4.39.0 supports up to 26.1; bots join with
  `version: '26.1'` and ViaBackwards translates to the Paper 26.2 server.
- The container is also attached to the `minecraft` network, only to read
  BlueMap at `http://minecraft:8100` (see Shared map). `velocity` is pinned
  with `--add-host=velocity:10.250.77.2` (its `mcbots` address) so the bots
  never reach it from a `minecraft`-network source, which BotGate refuses.
- Logins are staggered (4.5 s apart); reconnects back off 5 s, 10 s, ... up to
  5 min (at least 30 s after "logging in too fast").

## Deploy / disable

Deploy like any lab change (see `bandit-lab-updates.md`). Port 8445 must be
served once: Serve and HTTPS Certificates are already enabled for the panel;
after the first activation run `sudo systemctl restart mcbots-https`.

Disable: set `bandit-lab.mcbots.enable = false;` (or remove the
`./services/mcbots` import in `hosts/bandit-lab/default.nix`) and deploy.
Immediate stop without a deploy: `sudo systemctl stop docker-mcbots mcbots-https`.

## Phone notifications

After an operator deploys this configuration, ntfy listens only on host loopback
(`127.0.0.1:2586`); `ntfy-https` serves it on the tailnet at
`https://bandit-lab.tail7facc9.ts.net:8447` (never Funnel). No public firewall
port is needed. Keep Tailscale connected on the phone.

1. Install the **ntfy** app from the phone's app store and allow notifications.
2. On bandit-lab, read the generated read-only login with this exact command:
   `sudo cat /var/lib/mcbots/ntfy/read-credentials`.
   Keep the password private; do not paste it into chat or commit it.
3. In ntfy's account/server settings, add the server URL above and the `phone`
   username/password. Add a subscription for topic **mcbots**, selecting that
   server (full topic URL: `https://bandit-lab.tail7facc9.ts.net:8447/mcbots`).
4. On Android, allow background operation/battery exemption for ntfy so its
   connection to the private server remains active. On iOS, the configured
   `upstream-base-url` sends wake-up poll requests through ntfy.sh/APNS; message
   content remains on this server and the phone fetches it over Tailscale.
   See [ntfy's iOS setup](https://docs.ntfy.sh/config/#ios-instant-notifications).

Messages cover deaths (with the reported cause), repeated failures/resting,
supply chest capacity and missing food/torches/pickaxes, completed shaft/room/
level/treefarm jobs, and worker processes absent for more than five minutes.
Minecraft reconnects alone do not trigger worker-loss notifications. Deaths
and worker loss use high priority; other messages use normal priority. The hub
limits each kind per bot to once in ten minutes and all publish attempts to
30 per rolling hour. Limits reset when the hub restarts; sends are best-effort.

Mute: use the subscription's **Mute notifications** setting in the ntfy app
(or disable that subscription's notifications in the phone settings). To turn
publishing off in a manual/laptop run, leave `NTFY_URL` or `NTFY_TOKEN` unset.
The lab hub gets its URL/topic declaratively and its token from a root-only
Docker environment file; workers never receive it.

`ntfy-seed` generates credentials once, atomically, in `/var/lib/mcbots/ntfy`
(mode 0700, files 0600), following the existing agent-token pattern. The native
ntfy service provisions two non-admin users into its StateDirectory auth DB,
`/var/lib/ntfy-sh/user.db`: `mcbots` can only write topic `mcbots`, and `phone`
can only read it. All other topic access, including anonymous access, is denied.
No credentials are stored in Git or SOPS. If Serve was not ready on first
activation, the operator can run `sudo systemctl restart ntfy-https` afterward.

## Dashboard

Open `https://bandit-lab.tail7facc9.ts.net:8445` from a tailnet device.
`tailscale serve` adds the header `Tailscale-User-Login`; the app answers 403 to
anything (HTTP or WebSocket) whose login is not in `ALLOWED_TS_LOGINS`
(`6FaNcY9@github`). POSTs and WebSocket upgrades also need a same-origin
`Origin`. Without `ALLOWED_TS_LOGINS` (laptop) the dashboard binds to
`127.0.0.1` only and refuses any other `DASHBOARD_HOST`.

![Dashboard on the local stage: two bots mining, queue, events, map](img/dashboard.png)

The map is at the top: terrain from BlueMap's low-res tiles (`GET /api/tile/<map>/<lod>/x<i>/z<j>.png`,
fetched server-side from `BLUEMAP_URL`, cached 5 min). Drag to move, wheel to zoom. Click a bot
(select it: map actions then go to that bot only; show card; centre; stop), a player (selected bot
or all bots: come, follow) or a spot (go here, at the surface height read from the tile).

**Markers** (stage 1 of `CONTROL-CENTRE-GOAL.md`): right-click or click a spot, "Add a marker here…",
name, kind (`supply`, `chest`, `site`, `home`, `afk`) and y (for a chest: the chest block's own height,
F3). Click a marker for its actions: chests (empty inventory here, re-arm, count), sites (work shift
for logs/stone/ores into the nearest chest marker, guard), AFK (park the bot, fighting off), go here;
move, rename, delete. The first overworld `supply` marker replaces `SUPPLY_CHEST` for all bots, the
hub and the keeper; the first `site` marker replaces `KEEPER_SITE`. Kept in `STATE_DIR/places.json`.
Laptop workers get the supply chest only when they connect.

Each bot card has an **In-game view** (also from the map menu): a 256x144 first-person picture (at most 150 ms of rendering per frame, at most one frame per 1 s or 4x its render time)
rendered on the server from the blocks the bot has loaded (`app/view.js`, `GET /api/view/<bot>.png`,
one frame per bot per 0.7 s, refreshed every second while open). Blocks are flat colours by name,
players blue and hostile mobs red boxes; no textures. Laptop workers (bot5) have no view yet.

**Settings** per bot (card, or map menu): fight hostile mobs on/off, fight range (2-16 blocks: the
bot walks up to a hostile this close, so skeletons no longer shoot it from afar), retreat below
health, eat below food. `POST /api/settings {"bot": "bot1", "settings": {...}}` (same-origin JSON);
kept in `STATE_DIR/settings.json`, on the lab the named volume `mcbots-state` (the only mount the
`lab-mcbots` check allows). Worker bots (bot16-bot18, laptop bots) use the same card: the hub validates and
stores the settings, forwards them to the worker (`settings` frame, validated again there), and sends them
with every `welcome`, so a changed value reaches a worker that was away and survives a restart of either side.

**Guard** job: `guard {x, y, z, radius}` or `guard {player, radius}` (radius 4-48, default 16). Until
stopped, the bot fights every hostile within the radius of the spot or player and walks back when
all is quiet. Map menu: "guard this spot" / "guard <player>"; composer: "Guard a spot", "Guard a player".

**Combat precision**: every swing lands exactly when the weapon is fully charged (sword 0.65 s,
axe 1.03 s) and is a critical hit (jump, strike on the way down: x1.5 and the crit sparkles); with
a sword and two or more hostiles together it is a ground swing instead, so the sweep hits all of
them. Live: two zombies killed in about 10 s, no server pull-backs. No sprint or strafing: movement
is where Paper pulls bots back.

**Torches** (setting "place torches where it is dark", on by default): during `mine`, `chop` and
`shift`, where the block light at the bot's feet is below 7 and no torch is within 5 blocks, it puts a
torch on a wall at head height (floor if there is no wall). Out of torches with coal or charcoal in
the inventory: it crafts 4 (one try per 5 min).

**Ore heights**: an ore job first digs down (or up) into the ore's band (iron 0..40, copper 30..70,
coal 40..130, gold -30..-5, lapis -15..15, redstone/diamond -60..-45, emerald 100..250; 26.2 keeps
the 1.18 distribution), ores outside the band count 4 extra per level, and when nothing is left in
reach it tunnels 32 blocks sideways (up to 6 times) instead of failing. Live: `mine iron_ore 8`
from the surface, 11 raw iron in 153 s, ending at Y 32.

**Staying put and kitted**: a shift never works more than 64 blocks (horizontally) from its chest;
an unreachable block makes the bot skip the whole vein around it (4 blocks) for 5 min; armour in the
inventory goes on at once; a log job without an axe makes a stone or wooden one first.

**Sealing**: water or lava next to a target block is plugged first: the bot places a rubble block
(cobblestone, cobbled deepslate, dirt, granite, ...) against the target's face towards the fluid,
then mines the target; without rubble it skips the block. Live: water above a test ore sealed with
granite, ore mined in 16 s.

**Jobs survive restarts**: every 2 s the running and queued `shift`, `guard`, `mine` and `chop` jobs
are saved to `STATE_DIR/jobs.json` (a mine/chop with what is left of its count) and queued again
once each bot is back online after a restart or deploy (a bot away for more than 5 min starts
empty). Worker bots count too: each worker reports its own list in the status frame, the hub saves it and
queues it again when the worker is connected and its bot idle (a worker that kept playing through a hub
restart is not given the job twice). A worker restarted *alone* is handled by the hub, which still has the bot's last reported list: it queues the jobs again when the bot is online and idle, within 5 min of the worker's hello (a plain reconnect of a worker that kept playing is not given them twice; `Stop` forgets them). A shift whose bot is far from the chest (respawned at world spawn) walks back first.
A **double chest** stays shut when either half is covered, so a bot checks both halves and digs away scaffold (dirt, stone, cobblestone) on top of the other half too (found live 2026-10-10: a covered second half gave `windowOpen did not fire` on every deposit). The other half is the one block that `facing` and `type` point to (the `left` half's partner lies clockwise of `facing`, the `right` half's counter-clockwise: north-facing left at x, right at x+1); a neighbouring pair or a single chest is never touched.

**Forests**: log jobs search 128 blocks and a log shift may work 128 blocks from its chest (64 for
stone and ore); with nothing left the bot walks on to new ground. Where a log came off dirt or grass
the bot plants the matching sapling again (live: `replanted birch_sapling at ...`), so the forest
around the chest regrows. Long walks go in 48-block legs.

**Junk**: during ore and log jobs, with fewer than 4 free slots, the bot throws away cobblestone
(keeping one stack), cobbled deepslate, dirt, gravel, granite, diorite, andesite, tuff and the like
(not what the job is mining). Torches never hang on a block of the job's target type.

**Targets**: `mine`/`shift` of an ore also take its deepslate variant; ores are searched within 128
blocks (no anti-xray on the server, so bots see ores through stone), nearest first so a vein is
finished; stone and logs prefer blocks at or above the bot (2 extra cost per level down).

One card per bot: an activity line in plain words ("mining stone 6/40 near -94
66 -2", "walking to the supply chest to deposit", "idle - no job", "dead -
respawning", "offline - last seen 3 min ago"), a progress bar for jobs that
count (a work shift has no end, so no bar), health and food, the held tool with
its durability (red below 15 %), inventory summary with free slots, host
(`@bandit-lab`, `@laptop (remote worker)`), position, and the queue with an x
to remove a queued job. A "problem" line shows the last error with its age
(grey after 5 min); a death clears itself on respawn.

Each card has "Give a job" (job types with fields; coordinates start at the
supply chest; "Run now" replaces the running job and the queue, "Queue" adds
behind it, "Stop" clears both). "Stop all" in the header and "Give the same job
to several bots" (select bots, none = all) work on many bots. "Come to me" uses
the player name typed into "your player name". The map shows bots, players,
mobs, chests/ores, claimed blocks (orange), the supply chest and the protected
areas (zoom with the wheel). "Advanced: debug" is the panel described below.

### Managing from the dashboard (phone friendly)

All write endpoints below are for humans only (same-origin JSON POST behind the Tailscale login
check, `TRUSTED_PROXIES` rule unchanged); the agent token is refused on them.

- **Projects** (`POST /api/project {bot, action: pause|resume|stop}`): one row per bot with a
  shaft/excavate/level/seal/rim/treefarm/homebed/build/grave job running, queued or remembered, with progress.
  The server remembers each bot's last project and its validated arguments in `STATE_DIR/projects.json`
  (any `/api/job`, also the agents', notes it; a stop marks it paused). Pause keeps it, Resume queues
  the *last project given to that bot* again, Stop forgets it. Pausing a *running* project is a bot stop, so that bot's queue
  goes too; a merely queued project is removed alone.
- **Quick actions** in every bot card: Stop, Home (`goto` the supply chest), Come to me (the "your player
  name" field), Rearm, Home bed (+ slot field: the slot is stored per bot in `crews.json`, unique, 0..13;
  blank = by crew order), and a job picker (any job type, arguments as JSON, validated by `VALIDATE`).
  There is no Graves button: the graves feature only queues a grave job at a death and keeps no list.
- **Supply chest** panel: the last count (age, who, free slots, contents) and warnings: full (< 4 free
  slots), no food, no torches/coal, no pickaxes, no saplings. "Count it" sends an idle bot. When the chest
  turns full one `alert` event is emitted (once per fill). Free slots come from `chest.inventoryStart`
  minus the stacks in it; an older worker that does not send them shows no "full" warning.
- **Crews and goals** (`GET/POST /api/crews`, `STATE_DIR/crews.json`): move a worker between agents, edit
  an agent's goal (max 1000 characters). Names must be `AGENT_BOTS`, an agent is never a worker, a worker
  is in at most one crew; a refused edit changes nothing. The agent service pulls `GET /api/crews`
  (the agent bearer may read it) every 30 s and uses it instead of `WORKERS_<agent>` / `AGENTS` in
  `default.nix`, which stay the defaults; "Reset to defaults" (`{crews: null, goals: null}`) restores
  them. A goal the agent set itself with `!goal` is kept until the stored goal changes.

### Agent decisions and `GET /api/decisions`

The lab's agent service (`hosts/bandit-lab/services/mcagents`, Andy-4.2 on the
Ollama container) posts every model reply with its bearer to `POST
/api/decision`; the dashboard keeps the last 200 apart from the events and shows
them under "Agent decisions" (newest first, same bot filter). Lead mode: bot1
is the agent and gives its workers (bot2-bot4, and bot16-bot18 from the
`mcbots-worker` container, which shares mcbots' network namespace) shifts with
`!assign`. Keep "Standing orders" off while the agent leads: the keeper would
hand the same bots its own jobs. Stop the brain without touching running jobs:
`sudo systemctl stop mcagents`.

### Slayer card (gaming PC) and `GET /api/slayer`

When the owner's PC serves the agents' model (llama-server on `slayerpc:8081`, reached on the
lab as `http://127.0.0.1:18081` through the lab tunnel), the dashboard shows a "slayer" card:
state (`serving`, `paused-game` while a game runs, `offline`), busy/idle, tok/s, requests today,
decisions lab vs slayer (last 24 h) and, when known, GPU use. Off by default: the card stays
hidden until the service has `SLAYER_URL` (for example `http://127.0.0.1:18081`; the container
must be able to reach it, so wire it together with the tunnel). The server polls every 10 s
with 2 s timeouts: `/health`, `/slots`, `/metrics` (llama-server needs `--metrics`; tok/s is
llama.cpp's average since start) and `/status.json` (not served by llama-server, so normally
absent). GPU numbers come from the optional `SLAYER_STATUS_CMD`, a JSON array run every 60 s
without a shell (5 s timeout, 4 KB output, JSON-validated), e.g.
`["ssh","slayer","type","C:\\bandit-ai\\status.json"]`; unset by default. See `tools/slayer/README.md`
for the file the PC writes. "Requests today" and the per-backend counts come from the decisions
log (`POST /api/decision` takes an optional `"backend": "lab"|"slayer"`, missing = lab), so a
busy day counts only the newest 200 decisions.

### Events and `GET /api/events`

The Events panel lists the last 200 events (job started / finished / failed /
stopped, death (with the cause from Paper's death message when it arrived in the
5 s before, e.g. `died at -278 46 -168: fell from a high place`), respawn, deposit, a bot skipping blocks another bot holds,
joined/left the game, a worker connecting or going offline). They live in a ring
buffer in the hub process (`app/events.js`, lost on restart); `GET
/api/events?since=<id>` returns `{lastId, events: [{id, t, bot, kind, text}]}`
with ids above `since`. Workers send theirs with their status frames; the hub
keeps only events for the worker's own bots, with a known kind and at most 200
characters.

Two event texts are read by the lead agent: a `build` or `excavate` that found nothing to do ends
`finished: ... - already complete (0 s)`, and a deposit names what went in (`deposited 64
cobblestone, 12 coal at the supply chest`, biggest four kinds). `/api/state` carries the supply
chest as the last bot saw it, `world.stock: {items, by, age}` (null before the first count).

The page's Content-Security-Policy allows exactly its own inline script and
style by hash (`default-src 'none'`, `connect-src 'self'`): no CDN, no other
origin. A change to the page changes the hashes automatically.

### Debug panel and `GET /api/debug`

The "Debug" section on the dashboard (collapsed by default; polls every 2 s while
open) shows per bot: how often the server pulled the bot back in the last 30 s
(red from 10), the current job step with its running time, pathfinder and
physics state (on ground, wall contact, velocity, pressed keys), the last error
with its age, and the last 30 s of positions as a small track. "Copy
/api/debug JSON" copies the same data for a bug report.

`GET /api/debug` returns `{generatedAt, windowS, bots: [{name, online, pos,
dimension, job{type,args,status,progress,runningS}, queue, combat, physics,
pathfinder, positions[{agoS,x,y,z}], corrections{total,last30s,lastAgoS},
lastError{message,agoS}}]}`. It sits behind the same login check as the rest of
the dashboard. Positions are sampled every 500 ms (rounded to 0.01) and kept for
30 s. The bot cards also show "pulled back N x in 30 s" when it is not zero.

## Hub: bots on other machines (laptop bot5)

The lab app is also the hub. A worker on another machine runs its own bots
(Mineflayer on that machine, joining Velocity from its tailnet address) and
reports to the hub; the dashboard then lists them next to bot1..bot4 and bot10 with host,
online state and last-seen, sends their jobs, and the hub decides every block
reservation so lab and laptop bots never dig the same block.

```bash
nix run .#mcbots-worker -- bot5          # on the laptop; Ctrl-C stops the bot
```

- Names must match BotGate (`bot5`..`bot99`) and not be one of the lab's
  `BOT_NAMES`. The laptop is admitted by its tailnet address as before.
- Wiring: the container publishes the worker port on `127.0.0.1:8096`;
  `mcbots-https` exposes it with `tailscale serve --https=8446` (tailnet only,
  never Funnel). The port serves nothing but the WebSocket upgrade on `/worker`
  and needs `Authorization: Bearer <token>`; everything else is 404. The
  dashboard (8445) stays limited to `ALLOWED_TS_LOGINS` and has no worker route.
- Token: sops secret `mcbots-worker-token` in `secrets/lab.yaml` and
  `secrets/bandit.yaml` (same value). The lab hands it to the container through
  `/run/mcbots/seed.env` (never the plain environment); the laptop reads
  `/run/secrets/mcbots-worker-token` (`nixos/secrets-workstation.nix`, owner
  `vino`, 0400; needs one `nrs` after the first pull). Rotate by setting both
  keys again, deploying the lab, `sudo systemctl restart mcbots-seed docker-mcbots`
  and `nrs` on the laptop.
- Lab workers: each worker container has its own credential, `sha256("mcbots-worker:<label>:<shared token>")` (written by `mcbots-seed` to `/run/mcbots/worker-<label>.env`; the hub derives the same from `HUB_WORKERS` in `default.nix`). It may run only the names listed for its label; the shared token (laptops) may run every other remote name, never a lab worker's. Refusal: `bot16 may not be run with this worker credential` / `... belong to a lab worker` (4003), also right after a hub restart. Laptop workers still share one credential.
- Names: a bot name belongs to the worker that first announced it, until the hub restarts. A worker is known by `wid` (an HMAC of its login seed, so it needs that seed; a worker without `wid` is known by its host label). Another worker holding the token is refused (`bot12 is taken by another worker`, close code 4003) instead of replacing the owner; the owner reconnects freely and takes a stale socket over. To hand a name to another machine, restart the hub (deploy).
- What a worker may do: act only for the names in its hello, claim at most 8
  blocks per bot, report mobs/blocks/status. Everything it sends is
  re-validated and size-capped on the hub (`hub.js`). Jobs go the other way
  and are validated on the hub first, then again on the worker.
- Reservations: the hub's `WorldModel` is the only table. A worker asks per
  block (about one tailnet round trip) before it digs; if the hub is
  unreachable it refuses ("hub unreachable: not digging without block
  reservations") instead of guessing. Claims of a worker that disconnects are
  freed at once; otherwise they expire after 2 min.
- Offline: a worker that disconnects (or goes silent for 30 s) stays in the
  list as offline with its last-seen time. `Stop` for "all" skips absent
  workers; naming an absent bot is an error. A worker keeps its bots playing
  while the hub is away and reconnects with back-off (1 s .. 30 s).
- Protected areas and the supply chest come from the hub (`welcome`), so the
  laptop needs no copy of them.
- Troubleshooting: `HTTP 401` = wrong or missing token; `HTTP 404` on
  `/worker` = old image or Serve not published (`tailscale serve status`, then
  `sudo systemctl restart mcbots-https`); hub log lines start with `[hub]`
  (`sudo docker logs --tail 50 mcbots | grep '\[hub\]'`).

## Laptop (stand-alone, without the hub)

```bash
BOT_NAMES=bot5,bot6 MC_HOST=100.125.161.81 nix run .#mcbots
# dashboard: http://127.0.0.1:8095
```

Other variables: `MC_PORT` (25565), `DASHBOARD_PORT` (8095). Use at most the
names not used by the lab. Ctrl-C quits the bots cleanly.

## Shared map and combat

All bots in a process share one world model (`app/world.js`), shown on the
dashboard radar and served by `GET /api/state` (`bots`, `world`,
`protectedAreas`; also `GET /api/world`) and over the WebSocket.

- Players: BlueMap `/maps/<map>/live/players.json` for `world`,
  `world_the_nether`, `world_the_end`, polled every 2 s (`BLUEMAP_URL`; empty
  disables). Players hidden from BlueMap are not seen. If BlueMap fails, the
  radar shows "unavailable" and bots fall back to entity tracking.
- Hostile mobs seen by any bot (30 s, at most 200), chests/barrels and
  diamond/emerald/ancient debris ore within 32 blocks of a bot (10 min, at most
  100). A bot waits up to 10 s before walking to or mining at a spot with a
  reported hostile within 8 blocks, then goes anyway.
- Access: BlueMap listens on the `minecraft` container; the bots container
  joins the `minecraft` network to read it. Paper there has `velocity.enabled`
  and rejects logins without Velocity's forwarding secret (config-derived, not
  tested at runtime); the container has no mounts or capabilities. It can also
  reach the VoxelDash panel port 7867 (password protected) there.
- `come`/`follow`: when the player is not tracked, the bot walks toward the
  BlueMap position (same dimension only; otherwise the job fails) and switches
  to the live player once visible. `come` allows 90 s plus 1 s per block of
  distance, at most 10 min.
- Combat (`app/combat.js`, every 500 ms): hostile mobs only, never players or
  animals. A hostile within 4 blocks is attacked with the best sword/axe in the
  inventory (swords before axes); creepers within 6 blocks are backed away from,
  not fought. Endermen, piglins, wardens, the wither/dragon, ghasts and breezes
  are never attacked. Below 8 health the bot retreats from hostiles within 16
  blocks until health is 12; its job pauses and resumes afterwards. Food below
  15 is eaten when nothing hostile is near, and a hurt bot (health below 20) eats
  already below food 18, because health only regenerates at food 18 or more
  (not raw chicken, rotten flesh, spider eyes, pufferfish, poisonous potatoes,
  golden apples).
  Defending inside `PROTECTED_AREAS` is allowed.

Dashboard radar: top-down, north up, centred on any bot or BlueMap player,
zoom by slider or wheel; shows bots, players, hostiles (fading), chests/ores
and the protected boxes (overworld only).

## Jobs

Each bot runs its queue one job at a time. Chat is never read as a command.

| Job | Arguments | Notes |
| --- | --- | --- |
| `goto` | x y z | walks within 1 block; gives up after 90 s; waits briefly if a hostile is reported at the target |
| `follow` | player | until `stop`; uses the BlueMap position when the player is not tracked; fails if the player is in another dimension or not on the map |
| `come` | player | walks to the player (BlueMap position when far); 90 s + 1 s/block, max 10 min |
| `mine` | block, count | `mine iron_ore 8`; nearest block within 64, best tool is equipped |
| `chop` | count | any `*_log` within 64 blocks |
| `shift` | block (or `logs`), x y z | work shift until stopped: mine/chop and deposit into the chest at x y z when full; stays within 64 blocks of it |
| `guard` | x y z or player, radius | fight hostiles within radius (4-48, default 16) until stopped |
| `craft` | item, count | crafts up to 64, making a crafting table first when needed |
| `smelt` | item, count | smelts up to 64 of an input such as `raw_iron` |
| `build` | blueprint, optional `remove` | places (or digs back) up to 75 plain blocks in a 5x5x3 box; see Building |
| `deposit` | x y z, optional `only` | puts everything except tools, food and crafting stock (planks, sticks, coal, torches, table, furnace) into the chest/barrel there; with `only` (an item name, `logs` or `coal`) just that kind, including what is normally kept |
| `withdraw` | item, count, x y z | takes up to `count` of an item (or `logs`) out of the chest/barrel |
| `stock` | x y z | opens the chest and reports its contents (changes nothing); for the supply chest the numbers go to the keeper |
| `place` | item, x y z | puts one block (chest, crafting table, ...) on top of the solid block under x y z; crafts it first when missing; refused inside protected areas |
| `hunt` | animal, count, x y z, optional radius | kills `count` (1-32) sheep, cows, pigs or chickens within `radius` (4-64, default 24) of x y z and picks the drops up; with shears a sheep is sheared instead (the sheep lives, one that gives no wool does not count); never named or baby animals, never in protected areas; a sword sweep that kills a neighbour counts too; fails with how many it got when none are left in range |
| `tidy` | optional x y z, optional `radius` 2-32 (default 16) | picks up the dropped items lying within `radius` of x y z (default the supply chest) one at a time, nearest first (`app/tidy.js`), then runs `deposit` on the supply chest (whatever `deposit` keeps stays: tools, food, planks, coal, torches; without a supply chest the items stay in the inventory). Never walks to an item inside a protected area, in lava, fire, a cactus or a cobweb; an item it cannot reach is tried twice, then left; stops after 60 visits or 3 minutes; Stop-safe; resumed after a death. Agents: `!collectDrops(radius)` (centred on where the bot stands; a foreman assigns it to a worker), `tidy` is in the agent token policy. Live on the stage 2026-10-10: 4 tossed cobblestone picked up in 2 s; with a chest, 2 items picked up and the whole inventory (228 cobblestone ...) deposited |
| `bed` | x y z, facing | a bed with its foot at x y z and its head towards `facing` (north/south/east/west): both cells must be free with solid ground below and outside protected areas; crafts it from 3 wool of one colour and 3 planks when the bot holds none (`need 3 wool of one colour` otherwise: hunt first); a bed already lying there is not placed again; then clicks it (at night sleeps in it for a moment), which sets the spawn point; the event `spawn set at x y z` says so |
| `homebed` | optional `slot` 0-13, or x y z (+ `facing`) | the bot's own bed in the storage rooms (`app/homebed.js`, agents: `!setHomeBed`). Slot = foot at z -213 (room 1, x -272..-266, y 58) or z -205 (room 2, slots 7-13), head towards north; without `slot` the crew order bot1 bot2 bot3 bot4 bot16 bot17 bot18 gives slots 0-6. Walks there, refuses protected cells, only clicks when a bed already lies there. Otherwise gets 3 wool of one colour (supply chest first; else `hunt` sheep here, then at 8 stops on a ring 70/140 blocks around the chest), planks (a log from the chest, else `chop`), crafts the bed, stands in the head cell facing north, places it and hands the click to `bed` (spawn set). |
| `grave` | x y z | walks to where a bot died, finds AxGraves' grave entity within 3 blocks, sneaks, right-clicks it (only the owner can), checks the inventory grew, puts on better armour, then deposits everything except tools, food and `KEEP_RE` into the supply chest; event `grave at x y z: N items back`; refused inside protected areas; fails `gave nothing` when it is not the bot's grave or already taken |
| `level` | x1 z1 x2 z2 (the shaft's box), y, optional top, length, branch | mining at one height of a shaft: see "Mining levels" |
| `seal` | x1 z1 x2 z2, y1, y2 | walls over the cave openings in the four side faces of a box (at most 24 x 24, 160 high; the shaft plus a margin): see "Sealing cave openings" |
| `treefarm` | x1 z1 x2 z2 | tree farm in an area of 3 x 3 to 24 x 24 until stopped: plants saplings (oak first, then birch, spruce, acacia, cherry, jungle; never dark oak or pale oak, which need a 2x2) on a 3-block grid on grass/dirt cells with 4 free blocks above, takes saplings from the supply chest when it has none, chops grown trees (only natural `*_log` blocks inside the area whose base stands on soil and that carry leaves; leaves stay), picks up saplings, apples and logs that fall inside the area, replants, uses bone meal if it has some, and puts the logs into the supply chest when the inventory fills or there is nothing to do. Fails with `no saplings` when the chest has none and nothing grows. Protected areas are skipped; the pathfinder may dig only logs and leaves on the way. Needs room in the supply chest (a full chest fails the job with `destination full`). Live (laptop, 2026-10-10): 4 saplings planted in 90 s, a grown oak chopped (4 logs), its drops and the saplings from decaying leaves picked up and replanted, Stop ends it as `stopped`. Agent command `!tendTreeFarm(x1, z1, x2, z2)` |
| `say` | text | up to 200 characters; text starting with `/` is rejected |
| `stop` | | clears the queue and stops walking/digging |

### Scan (`GET /api/scan/<bot>`)

`app/scan.js` `scanAround(bot, r = 10)` is a small text map for the Andy agents: everything relative to the bot
(`dx,dy,dz`: +x east, +y up, +z south; N is -z), under 300 characters, most dangerous first: lava and water
within 4 blocks (nearest of each, `x2` = how many), `drop E6` (a fall of more than 3 right next to the bot),
`mobs zombie 7m` (hostile, within 16, nearest 4), `up 3 exits E,S,W` (free blocks above the head, directions
with a free 1x2 cell next to the bot), `items 2 near(3,0,0) oak_log` (dropped items within 10), chests, beds,
furnaces and crafting tables (nearest 4, a bed or double chest once), `ores coal(-1,-1,0) ...` (nearest 6).
Too long: the least important tokens go first; `data` keeps the full lists. The endpoint returns `{text, data}`;
for a bot of a worker container the hub asks the worker (`scan_req` / `scan` messages, like `view_req`),
waits up to 2 s and reuses an answer for 2 s (404 offline, 503 no answer). The agent bearer may read it, for
its own agent bots only. The agent service puts its bot's text in the prompt as `Around you (...)`, a 120
character `around:` line under each worker for a foreman, and answers `!nearbyBlocks` with it.

### Beds and respawn (R5)

`hunt` and `bed` (`app/hunt.js`; the agents reach them as `!huntAnimals(type, num)` and
`!placeBed(x, y, z, facing)`, and `hunt`/`bed` are in the agent token policy). Minecraft sets the spawn point
when a player right-clicks a bed, by day too ("Respawn point set"); sleeping is not needed. Seen live on the
stage (bot12, 2026-10-10): 3 summoned sheep killed in 11 s, 4 in 21 s including the drops; a bed crafted from
white wool and birch planks (the bot placed its own crafting table), placed and clicked in 12 s with
`spawn set at`; after `kill bot12` the bot came back next to the bed, not at the world spawn. Traps found:
a sword sweeps and kills the sheep beside the target (counted now); the bed's head block reaches the client a
moment after the foot, so the job waits for both before it judges the facing; with wool but no planks `ensureItem` picked the "any bed + dye" recipe and failed (`need 1 more bone`), so `bed` makes the 3 planks first and says `need 3 more planks and have no logs (chop first)`; a bed whose head cell hangs over a
pit is refused beforehand (`nothing solid under ...`). The night path (`bot.sleep`, refused near monsters or when
too far) falls back to the plain click; it was not run live (the stage was in daylight).

`homebed` is the one-per-bot version: each bot sleeps in its own slot so a death respawns at the base. The
slots are the south row of the rooms because `bed` stands behind the foot, which is the wall there; `homebed`
stands in the head cell instead (mineflayer's `placeBlock` would turn the bot towards the block, so the job sets the
yaw itself and places with `forceLook: 'ignore'`). Animals are sent to a client only within ~48 blocks, so a
search that sees no sheep from the base finds none: on 2026-10-10 neither the base, nor a ring of 8 stops up to 140
blocks out, had sheep, so wool has to come from the supply chest. Not run live yet: placing the bed (needs 3 wool:
`/give bot14 white_wool 3` on the stage).

### Graves (AxGraves)

A dying bot leaves its items and XP in an AxGraves grave for 24 h (then they drop). `app/graves.js`: on its own
death a bot queues `grave` at the death position right behind the re-arm (before the interrupted job continues),
only for an overworld death within 1500 blocks of the supply chest, outside protected areas, and not when it died
on the way to a grave (no loop at a deadly spot). Agents reach it as `!collectGrave(x, y, z)` (`grave` is in the
agent token policy). The grave is two packet entities at the death block: an `armor_stand` (type `living`) and a
`text_display` (type `other`); the job tries the nearest of the entities within 3 blocks. mineflayer's
`bot.activateEntity` always sends `sneaking: false`, which AxGraves ignores, so `graves.js` writes `use_entity`
itself (interact-at, then interact, `sneaking: true`). Live on the stage (bot11 578 items, bot13 432 items,
2026-10-10): kill -> respawn -> re-arm -> grave -> deposit, about 45 s with the walk from spawn, the click itself
under 1 s.

### Mining levels (`level` job)

`app/level.js`. At height `y` (the tunnels' feet level; the bot stands on the shaft's stair step of layer `y - 1`; `y` must lie
between the shaft's bottom + 1 and top - 1) the bot digs a 2-high tunnel straight out of the middle of each of the shaft's four
walls (`length` blocks, default 32, 4-64) and, every 3rd block, a 1 x 2 branch to both sides (`branch` blocks, default 8,
0-16): two blocks of rock stay between neighbours, so every ore of the layer shows. Every ore that touches a dug block is
mined, with its vein (up to 24 blocks, within 8 of the dug block). A tunnel needs about 770 columns at the defaults.
Arguments are the shaft job's (`x1 z1 x2 z2`, `top` default 80) plus `y`, so the same box serves `shaft`, `rim` and `level`.

- Several bots on one level: each bot starts on another arm (the name decides, `armOrder`), works the other arms afterwards, and
  every block is claimed through the shared table (`claims`), so none is dug twice. A block held by another bot makes the arm
  wait for the next pass (3 passes, 3 s apart); the event says which tunnel was left, run the level again for it.
- Rules like `excavate`: natural ground only (a chest, torch or cobblestone ends the arm there), never protected areas or
  the supply chest's floor, no digging next to a fluid (`guardDigs`; a fluid neighbour is plugged when possible, else that tunnel
  ends), gravel that falls into the tunnel is dug again. `upkeep` places torches, wears armour, replaces the pickaxe and
  deposits into the supply chest when the inventory fills. A Stop, a death or a restart resumes it (`KEEP`/`RESUMABLE`); cells
  already dug cost nothing.
- The walk down uses the shaft's own stair, 16 layers per leg, and waits for a fight to end (a creeper backing the bot off
  changes the pathfinder's goal, so the walk is repeated up to 4 times).
- Agent command `!mineLevel(y)` (uses the lab shaft box, `SHAFT=x1,z1,x2,z2` overrides in `tools/mcagents`); a foreman only assigns it.
- Live (2026-10-10, local stage, bot11/bot12 against the lab world, shaft -291 -222 -276 -207): y 40, length 6, branch 4: 88
  columns in 704 s, 9 ores (a copper vein: 32 raw copper), all four tunnels. y 36 (bot12): 889 s, 4 ores, three tunnels (the
  fourth was unreachable while a creeper kept changing the pathfinder's goal; that is why walks now wait and retry). A Stop
  and a death/resume work. Not seen live: two bots digging at once (only the claim logic is unit-tested), because unlit
  tunnels without torches filled with zombies and killed the stage bots (no coal, no armour): give level bots coal or torches.
  Level heights worth queueing: y 16 (iron peak, plus coal and copper), y -54 (diamonds, redstone; lava lakes start at -55, so
  expect plugged fluids), optionally y -16 (gold) and y 0 (lapis).

### Sealing cave openings (`seal` job)

`app/seal.js`. Hostiles walked into the shaft and its tunnels from natural caves (lab 2026-10-10: 11 deaths in 10 minutes), and light
blocks do not stop mobs arriving from the sides. `seal` scans the four side faces of a box (two corners and a y range, at most
24 x 24 wide and 160 high, so the shaft plus a margin) and puts a block into every face cell that is air (`air`/`cave_air`) and has a
non-solid block just outside the box. The top and bottom faces are never walled (the shaft stays open).

- **Place only.** The pathfinder may neither dig nor scaffold during the job (`digOnly` matches nothing, scaffolding is empty; both
  come back in `finally`), so natural ground is never removed. The bot stands inside the box, off the boundary when it can, and
  places against a solid neighbour of the cell. Water and lava on the boundary are counted and left alone; an air cell next to
  fluid outside is walled like any other.
- **Left alone:** cells in protected areas, within 1 block of the supply chest, within 1 block of a bed, `reserved()` cells, cells
  open to the sky (nothing solid above them within 40 blocks, leaves do not count: the surface around the shaft is the `rim` job's
  business), cells not loaded yet. The info line at the start counts them.
- **Material:** cobblestone, else cobbled deepslate, else dirt. With none carried it takes up to 128 cobblestone from the supply chest
  (`withdraw`); with no chest, or an empty one, the job fails with `out of wall blocks ... (N walls placed this run, M openings were left)`.
  A torch goes on the inside face of a new wall when the bot carries one and none shines within 5 blocks.
- **Bounded:** at most 300 walls and 30 minutes per run; then the job ends with an info note (`capped at 300 walls this run, run it
  again for the rest`). A cell that fails twice (no path, no stand, did not take) is given up; the job then fails with `N walls placed, M
  openings left (unreachable, ...)`.
- **Stop-safe and resumable** (`KEEP`/`RESUMABLE`): the world is the state, so a Stop, a death or a restart scans again and places
  only what is still open. A fight that takes the pathfinder restarts the job body after the fight (the counters start again).
- Agent command `!sealArea(x1, z1, x2, z2, y1, y2)` (workers; a foreman assigns it). It refuses a box whose side wall runs through the
  shaft footprint (`SHAFT`), which would cover the stairs along the shaft walls. Dashboard: job picker `seal`, listed as a project.
- **Existing tunnels are plugged too.** A mining tunnel (`level` job) that leaves the box is an opening like any cave: sealing puts
  cobblestone in its mouth, and `level` (natural ground only) cannot dig that out. Mine the levels first, or open the plug by hand.
- Live (2026-10-10, local stage, bot11 against the lab world, box -293 -224 -274 -205): y 50..64: 136 openings, 45 of them open to the
  sky and left; the bot mined 120 stone as it went and ended with 24 left that no path reached (`No path to the goal` for stands up
  on the shaft's cliff). A Stop ended the job as `stopped` after 3 walls, a restart resumed it (`resumed after restart: seal`, 86 -> 77 openings).

## Long runs

What a bot does on its own while a `mine`, `chop` or `shift` job runs (`upkeep()`
in `app/bots.js`, checked before every block):

- **Iron gear** (`ensureGear`, `app/gear.js`, once per 5 min, only when the food is fine and there is
  something to do): 3 or more raw iron and coal or charcoal in the inventory are smelted into ingots (no
  more than the missing gear needs, and never the ore the job itself is mining, which belongs in the
  chest). Then, with the ingots on hand and in this order: iron pickaxe (3), iron sword (2), then the
  cheapest empty armour slot first (boots 4, helmet 5, leggings 7, chestplate 8), worn at once. Iron
  or better already held (a diamond pickaxe counts) or any piece already in a slot is never replaced.
  A failure (no wood for the sticks or the table, no cobblestone for the furnace) is an info event and the
  job carries on. Live on the local stage (bot11, 2026-10-10, `mine stone`, given 20 raw iron, 4 coal, 4
  logs, 16 cobblestone): `smelted 20 raw iron`, then pickaxe, sword, boots, helmet (6 ingots left, leggings
  need 7); a second job after 10 more raw iron made leggings and chestplate, and no second pickaxe.
- **Broken tool**: no pickaxe that can harvest the block: craft a stone pickaxe,
  else a wooden one (chopping 3 logs first when it has no wood), else take one
  from the supply chest; then carry on where it was. Chopping without an axe is
  fine, so a broken axe is not replaced.
- **Hunger**: food below 14, none in the inventory and a supply chest set: walk
  there and take food (the `rearm` routine), at most once per 10 min. Every withdrawal in `rearm` is allowed to fail (full inventory, another bot took the last one): it is logged as `re-arm: could not take ...` and the armour, food and equip steps still happen. Food comes before the spare pickaxe and the 2 logs. Planks that could not be crafted show as `no planks` in the job's progress. The
  existing combat loop eats from the inventory below 15 (below 18 while hurt).
- **No wood for torches**: a `mine` or `shift` on an ore, with a supply chest set and
  fewer than 2 logs and fewer than 8 planks in the inventory, first takes 4 logs from the
  chest (at most once per 10 min; `rearm` does it every time, at its end). No logs in the
  chest is an info event, not a failure. Live (bot6, `mine iron_ore 5` from the surface):
  `took logs from the supply chest for torches`, then 3 torches placed underground.
- **Full inventory** (fewer than 2 free slots) in a job that is not a `shift`:
  deposit into the supply chest and carry on. A `shift` deposits into its own
  chest. Without a chest the job fails with a clear message.
- **Death or disconnect**: the running job (`mine`, `chop`, `shift`, `goto`,
  `deposit`, `follow`, `come`) goes back to the front of the queue behind the
  re-arm, keeps its count (`collected`), and the bot first walks back to the
  last block it worked on. Nothing runs while the bot is dead. A job interrupted
  more than 3 times is given up ("gave up" event). A job you stopped is never
  resumed. `craft`/`smelt` are short and start over.
- **Unreachable block** (`could not reach`): skipped for 5 min; five in a row end
  the job. A dig the server never answers is abandoned after 25 s; a walk that
  never settles is ended by the 90 s deadline (`pathfinder.stop()` alone does not
  settle a pending `goto`, `setGoal(null)` does).
- **Claims** that expired no longer count toward the per-bot cap of 8 and are
  pruned; a remote bot offline for over an hour leaves the list; a wrong token
  earns the guesser a 429 after 20 tries a minute but never locks the real
  worker out.

## Standing orders (keeper)

A switch on the dashboard ("Standing orders") that keeps the supply chest stocked
(`app/keeper.js`). Quotas are declared in `default.nix` (`KEEPER_QUOTAS`, now
`logs:64,cobblestone:128,coal:32,torch:64,raw_iron:16,iron_pickaxe:2,iron_sword:1`; optional `KEEPER_SITE=x,y,z` to walk to
before chopping or mining). Without `SUPPLY_CHEST` or quotas the panel is absent.

- **Off after every restart.** Switching on does nothing but read the chest and
  plan; switching off stops planning (bots finish their jobs; use Stop to end them).
- **Stock** comes from whichever bot last opened the chest (`deposit`,
  `withdraw`, `stock` jobs, also from laptop workers). Numbers older than 15 min
  or unknown: an idle bot is sent to count (`stock` job).
- **Planning** every 5 s: the first quota below target with nobody on it goes to an
  idle bot (idle for 10 s, no queue, not dead, online; lab bots and connected workers
  alike), at most two bots at once, at most 64 items per chain, as normal queued
  jobs: logs = `chop` + `deposit only logs`; cobblestone = `mine stone` + `deposit
  only cobblestone`; coal = `mine coal_ore` + `deposit only coal`; torch = `withdraw
  coal`, `withdraw logs`, `craft torch`, `deposit only torch` (only when the chest
  already holds the coal and a log); raw_iron = `mine iron_ore` + `deposit only raw_iron`; iron_pickaxe
  and iron_sword = `withdraw` raw iron (3 or 2 per tool), coal, 8 cobblestone and logs, `smelt`, `craft`,
  `deposit only <tool>` (blocked until the chest holds all of it; `rearm` hands out the best pickaxe and sword).
  The stone pickaxe quota was dropped for this kit; `PLANS.stone_pickaxe` is still there. Everything shows up in the cards, the event log
  ("keeper") and can be stopped like any other job.
- A chain that ends without the chest getting more of the item puts that item on a
  10 min cooldown (no ore nearby must not become a loop). Items without a recipe
  in the keeper show "no way to make this".
- Bots dig where they stand (nearest blocks within 64); set `KEEPER_SITE` if the
  spawn surroundings should stay untouched. Protected areas stay protected.
- API: `GET /api/keeper`, `POST /api/keeper {"enabled": true|false}` (same-origin
  JSON only); the state is also part of every `/api/state` and WebSocket frame.

![Standing orders panel: quotas, stock and who works on what](img/standing-orders.png)

## The plan (R7, `app/plan.js`)

One ordered list of base objectives that the hub works through **without any LLM**, so it keeps
going when every model backend is down. It is built like the keeper: deterministic, data driven,
restart safe, and **off by default**. Stage A (the scheduler), B (keeper-driven quotas) and C (role
chains for idle bots) ship together.

- **Enable:** set `PLAN_ENABLE = "1"` and `PLAN_ROSTER = "bot11,bot12"` (bots the plan may task; none
  may be in `AGENT_BOTS`, the config refuses it) in `default.nix`, or in the environment of a local
  stage. A "Plan" panel appears on the dashboard. The plan still starts **switched off after every
  restart**; switch it on in the panel or `POST /api/plan {"enabled": true}`. Same-origin JSON only;
  the agent token cannot reach it. "Stop all" switches it off too.
- **What it does:** `app/plan-config.js` lists the objectives (geometry of this base: base box,
  base chest -271 66 -214, shaft x -291..-276 / z -222..-207, tree farm, storage room at y 58):
  home beds, stock basics, shaft to ore, storage room, tree farm, iron quota, iron tools. An
  objective is *keeper-driven* (the plan borrows the Keeper with the objective's quotas, the base chest
  and only the roster bots, and gives it back when the objective ends) or *direct* (job chains for
  idle roster bots; only empty slots are filled, a shaft is cut into one disjoint strip per bot).
  It never replaces or stops a running job and never takes a bot with a job or a queue.
- **Order and trouble:** an objective waits for its `needs`. A chain that fails is retried after
  10 min; 3 failures, or hours without progress, block the objective: it is *parked* (later steps
  need it; the plan goes on with independent ones) or *skipped* (nothing needs it). The panel has
  `retry` and `skip` per objective (`POST /api/plan {"retry": id}` / `{"skip": id}`). Standing orders
  switched on by hand are never taken over: the plan waits.
- **State:** `STATE_DIR/plan.json` (done, skipped, blocked, slots and results). Done objectives stay
  done; the rest is re-read from the world, so a deploy loses nothing.
- **Limits:** the plan uses the base chest from `plan-config.js`, but `homebed` and `treefarm` read
  the bots' own supply chest (`SUPPLY_CHEST`/a `supply` marker): put a `supply` marker on the base
  chest first. The shaft, storage-room and iron-tools chains are untested on the real base.
- **Stage test (2026-10-10, bot11 and bot12 on the laptop, roster of two, other objectives skipped):**
  `home-beds` handed `homebed 7` and `homebed 8` to the two idle bots at once; both failed on the real
  base (room 2 is not built: "cobblestone is in the way at -272 58 -206", "No path to the goal"), the
  plan logged each failure and waited 10 min instead of resending. After `skip` on `home-beds` it moved to
  `stock-basics`: the keeper was borrowed (plan chest, roster bots only), bot11 counted the base chest
  in 16 s (logs 95, cobblestone 578), bot12 started `mine coal_ore 32`, the panel showed 50% and
  "short: coal 0/32, torch 0/64". Skipping the last objective gave the keeper back (its own
  quotas and chest) and "Stop all" switched the plan off. The base chest was full (0 free slots).

## Building (`build` job)

Status 2026-10-10: built (`app/build.js`), unit-tested with a fake world in `app/test.js`, and
live-tested on the local stage: bot6 built a 3x3 cobblestone pad at -121 77 9 (west of the
protected spawn box, in the area earlier bot tests dug) in 7 s and removed it in 58 s, getting all
9 blocks back; 0 server pull-backs, 19 claims granted, 0 refused.

**B3 (2026-10-10): a build takes its missing blocks from the supply chest.** Before placing,
`build` counts what the blueprint still needs against the inventory; for each missing item it
runs the `withdraw` job against the supply chest for exactly the missing count (never in `remove`
mode, a stop is honoured between items). An item the chest does not hold is not an error yet;
after all items the job recounts and fails with `missing material: 9 cobblestone (not in the
supply chest either)` if anything is still short (without a supply chest the message has no
suffix). Live on the local stage (bot6, chest at -116 77 9, pad at -121 77 9): 9 cobblestone in
the chest, bot6 carrying none, `build` finished in 3 s including the withdrawal, chest 9 -> 0,
9/9 cells placed, 9 claims granted, 0 refused, no pull-back; `remove` took 40 s and gave all 9 back;
a second build with chest and bot empty failed with the message above (before B4). Not yet:
several bots on one build live (claims are shared, untested), a dashboard form (API only).

**B4 (2026-10-10): the builder gathers what is still missing.** After the chest, `build` gathers
the rest itself with child jobs (`GATHER` in `build.js`; the event `build gathers: mine stone x9`
marks each one): `cobblestone` = mine stone, `dirt` = mine dirt, `stone` = mine stone, then
`smelt cobblestone` (8 more stone for a furnace and a `chop` of 2 logs for its table when neither
is in reach, `coal_ore` for fuel when the bot carries none; one smelt per 64). Anything else
(logs, planks, glass, ...) fails before any job runs with `cannot gather 2 oak_planks yet`. The
job recounts afterwards; if drops were lost it gathers again, but never more than 2x the blueprint's
block count in total (`missing material: ... (gathered 18, the limit is 18)`). Building `stone` also
keeps cobblestone out of the pathfinder's scaffolding. Never in `remove` mode. Live on the local
stage (bot6, no supply chest, no cobblestone carried, pad at -121 77 9): `build` ran `mine stone
x9` and placed 9/9 in 23 s, 18 claims (9 dug, 9 placed), 0 refused; `remove` took 36 s and gave 9
cobblestone back. Not live-tested: the `stone` path (furnace, coal, smelt) and `dirt`; they are
unit-tested as a plan only. Limits: the mine job picks stone anywhere within its leash, so a
build over ground the bot also mines can lose supporting blocks; one bot gathers sequentially.

```bash
# blueprint relative to the origin; same-origin JSON, as for any job
curl -X POST http://127.0.0.1:8095/api/job -H 'Content-Type: application/json' \
  -H 'Origin: http://127.0.0.1:8095' -d '{"bots":["bot6"],"type":"build","args":
  {"origin":{"x":-121,"y":77,"z":9},"blocks":[{"x":0,"y":0,"z":0,"block":"cobblestone"}]}}'
```

Add `"remove": true` to dig the same blueprint back out. It removes **only blocks a build
placed** (a record per dimension and blueprint, kept in the bot process's memory): a matching
block that was there before stays, and without a record (after a restart) remove is refused.
Rules: plants from a fixed list (grass, flowers) in a target cell are broken first; anything
else there, a torch or redstone too, is "in the way" and fails the job. The pathfinder may not
dig, place or spend the blueprint's own blocks as scaffolding inside the build's box while the
job runs. A Stop is checked after every walk and equip, right before a block is placed or dug.
The job fails after 60 s without progress (held or unreachable blocks), a block that will not
come out is given up after 3 digs, and build jobs survive a restart (placed blocks are skipped).
These rules come from Codex's MC-3 review (2026-10-10).

- **Blueprint**: JSON `{"origin": {"x","y","z"}, "blocks": [{"x","y","z","block"}]}`
  with x, y, z relative to the origin, `block` a plain block name (no states, no
  containers, no gravity blocks, no liquids, no doors). At most 75 blocks and a
  5x5x3 bounding box; the origin must not be inside a protected area, and every
  target position must be air (or replaceable: grass, flowers) with a solid or
  already planned block under or beside it.
- **Order**: bottom layer first (y ascending), then z, then x, so every block has
  a neighbour to be placed against. A block waits until that neighbour exists.
- **Scaffolding**: none. The height limit of 3 keeps every target within reach
  (4.5 blocks) from the ground beside the structure; bots stand outside the
  footprint (`GoalPlaceBlock`), never pillar, never dig to make room. A target
  that is not reachable from the ground is reported, not worked around.
- **Several bots**: each takes the next free block through the existing claim
  table (key `dim:x,y,z`, the same as for digging, so a dig and a placement can
  never meet on one block), places it, releases it, and takes the next one. A
  `build` job is "place blocks of this blueprint until none is left", so any
  idle bot can join by queueing the same job.
- **Material**: counted up front from the blueprint; the job fails before
  placing anything when the inventory lacks it (`missing material: 3 stone`).
- **Undo**: a `build` with `remove: true` digs the same blueprint top-down with
  the same claims and keeps the blocks; the live test would end with it.
- **Tests first**: pure functions for validation (bounds, protected areas,
  allowed blocks), ordering and the "has a neighbour" rule, with a fake world,
  before any bot places a block.

## Limits

- Bots defend themselves against hostile mobs only (see above). They avoid
  digging into fluids or drops (see Sealing) but do not recognise players'
  builds: the only protection is `PROTECTED_AREAS`, where the pathfinder may
  neither break nor place. They cannot cross dimensions.
  `mine`/`chop` do break blocks: do not point them at player builds.
- Pathing uses Mineflayer's default movements without sprint, parkour or
  diagonals (server pull-backs), so it may dig through and bridge over blocks
  outside protected areas; a goal it still cannot reach is reported as
  "could not reach".
- BotGate admits names `bot0`..`bot99` by source address, and the mcbots container is one address on the `/29` network (gateway .1, Velocity .2), so the `/29` does not limit the bot count (checked 2026-10-10 against `BotGate.java` and `minecraft/default.nix`). Bots log in 4.5 s apart because Velocity rate-limits logins per address. CPU is the real limit: one Node process (see Performance).
- The dashboard trusts the `Tailscale-User-Login` header. Only `tailscale serve`
  (host) and containers on `mcbots` (Velocity) can reach it; keep it that way.

Reservation counters: `/api/debug` shows per bot `claims {granted, refused,
timedOut}` (timeouts = the hub did not answer within 3 s) and, for remote bots,
a `workers` summary per host; the Debug panel prints them as "reservations".

## Shipping to the lab

`tools/ship-claude [--dry-run] SHA...` prepares a ship from a branch: clean
detached worktree on `origin/main`, `cherry-pick -S` (your GPG key), signature
check, build of the committed `bandit-lab` revision, then it prints the exact
`git push origin HEAD:main` line and stops. It never pushes; the push deploys
within the hour. `--dry-run` skips signing and the build. Test:
`tools/ship-claude.test.sh` (throw-away repos, asserts nothing is pushed and the
dirty tree does not leak).

## Troubleshooting

- Bot offline, "logging in too fast" / throttled: wait; the runner backs off
  itself. Do not restart repeatedly.
- Kicked with a not-whitelisted/online-mode message: BotGate refused it. Check
  `sudo docker logs velocity 2>&1 | grep -i botgate` for the decision line (name
  pattern or source address). The name must match `^bot[0-9]{1,2}$` and come
  from the allowlisted source.
- Other Velocity problems: `sudo docker logs --tail 100 velocity`.
- Dashboard: `sudo journalctl -u docker-mcbots -u mcbots-https -n 50`,
  `sudo docker logs --tail 100 mcbots`. HTTPS unreachable: `tailscale serve status`,
  then `sudo systemctl restart mcbots-https`. 403: your Tailscale login is not in
  `ALLOWED_TS_LOGINS`, or the request bypassed `tailscale serve`.
- Bot stuck at a block (dashboard shows the same position, ~20 server
  corrections per second, "breaking the block frees it"): Paper 26.2 refuses a
  position whose box touches a block face exactly (gap 0.0), while a gap of
  1e-6 is accepted. Mineflayer's collision ends exactly flush, so the server
  pulled the bot back every tick. `app/physicsfix.js` makes every horizontal
  collision stop 1e-4 short (found 2026-10-08 with raw position packets against
  a one-block step; fixed and checked with 3 round trips to -104 71 -7, 0
  corrections). Widening the player box instead does not work: prismarine-physics
  lets a box that already overlaps a wall walk straight through it. If it
  returns, count `forcedMove` per bot first; `unwedge()` in `bots.js` only
  re-centres as a last resort.
- "digging X at ... got no answer": the server never confirmed a break within 25 s.
  `digAt()` now stops the dig, waits up to 3 s until the bot is on the ground and out of
  water, and digs once more; the first event says `trying once more: held ..., onGround ...,
  inWater ..., effects ..., dist ..., est ... ms`, a second failure says `skipped`.
  Measured 2026-10-10 (bot6, `mine redstone_ore 16` at y -47..-55): 5 first digs got no
  answer, all with the right pickaxe held, on the ground, dry, no effects, 1-3.5 blocks
  away, and all 5 worked on the second try, 0 skipped. So the cause is not the held
  item, airborne or water; it is a lost first dig that a fresh one fixes (a rejected or
  ignored start packet is the likeliest, unproven). Separate finding: minecraft-data
  gives ores the material `incorrect_for_wooden_tool` instead of `mineable/pickaxe`, so
  mineflayer's `digTime` ignores the pickaxe speed for every ore (`est 6750 ms` for
  deepslate redstone with a diamond pickaxe; vanilla takes about 840 ms).
- Image changed but the old one runs: the image tag is the Nix store hash;
  `sudo systemctl restart docker-mcbots` after activation.

## Performance

Profile 2026-10-10 (local stage, four bots: log shift, stone shift, coal mine, idle; 10 min, `NODE_OPTIONS="--cpu-prof"`): the process was busy 52 % of the time (about 0.6 of a core) and the top self-time was the pathfinder asking for blocks: `Block`/`fromStateId`/`getBlockEntity`/`Biome` in prismarine (about 111 s of 319 busy seconds), because each A* node looks at the same neighbours dozens of times and every lookup built a new Block. `app/pathcache.js` now returns the same Block within a 100 ms window; the same run then needed 262 busy seconds (-18 %) and the Block construction fell to about 46 s. The next items are the pathfinder's own `digTime`, `bestHarvestTool` and `getNumEntitiesAt`. Runs differ with what the bots happen to do, so compare busy seconds over equal mixes only.
