# Minecraft bots (Mineflayer)

Phase 1+2 of the bot system: Mineflayer bots join Paper through Velocity and
BotGate and are controlled from a small web dashboard. Code:
`hosts/bandit-lab/services/mcbots/` (`app/` is the Node app, `default.nix` the
lab deployment). Crafting and schematic building are later phases; a new job
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

## Dashboard

Open `https://bandit-lab.tail7facc9.ts.net:8445` from a tailnet device.
`tailscale serve` adds the header `Tailscale-User-Login`; the app answers 403 to
anything (HTTP or WebSocket) whose login is not in `ALLOWED_TS_LOGINS`
(`6FaNcY9@github`). POSTs and WebSocket upgrades also need a same-origin
`Origin`. Without `ALLOWED_TS_LOGINS` (laptop) the dashboard binds to
`127.0.0.1` only and refuses any other `DASHBOARD_HOST`.

The page shows every bot (online, health/food, position and dimension, job and
queue, inventory summary, last error). Pick a target (one bot or `all`), then
enqueue jobs. "Come to me" uses the player name typed into "your player name".

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
reports to the hub; the dashboard then lists them next to bot1..bot4 with host,
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
  15 is eaten when nothing hostile is near (not raw chicken, rotten flesh,
  spider eyes, pufferfish, poisonous potatoes, golden apples).
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
| `deposit` | x y z | puts everything except tools and food into the chest/barrel there |
| `say` | text | up to 200 characters; text starting with `/` is rejected |
| `stop` | | clears the queue and stops walking/digging |

## Limits

- Bots defend themselves against hostile mobs only (see above); they do not
  avoid lava or players' builds beyond not tunnelling or placing blocks while
  walking, and they cannot cross dimensions.
  `mine`/`chop` do break blocks: do not point them at player builds.
- Pathing cannot dig or bridge, so a goal behind solid rock is reported as
  "could not reach".
- Velocity admits at most the `/29` network: gateway, Velocity and 4 bots.
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
- Image changed but the old one runs: the image tag is the Nix store hash;
  `sudo systemctl restart docker-mcbots` after activation.
