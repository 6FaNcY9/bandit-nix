# Autopilot report

> **Status 2026-10-10:** everything below was shipped to `main` through `tools/ship-claude`,
> including the 2026-10-09 evening work. Still only on `claude/autopilot`: `mcbots-soak` and
> a few docs/hub commits (`git cherry origin/main claude/autopilot`). `KEEPER_SITE` is set in
> `default.nix`; a `site` marker overrides it. Next goals: `docs/NEXT-GOALS.md`.

Branch `claude/autopilot` (worktree `~/src/bandit-nix-auto`). Nothing pushed to `main`, no
deploy, no `flake.lock`/secrets change, no restart. Commits are unsigned; `tools/ship-claude`
re-signs them. Local stage = `node app/server.js` with bot6+bot7 against the lab game server.

## M1 - ship list for what was already on the branch: done

`9e750eb 68595ab 21db706` are already on `main` as `814bc41 2699425 e7f7768` (the app/ tree of the
branch equals main; only docs differ), so there is nothing left to ship for them.

Found and fixed while live-testing (both ready to ship, mcbots-only):

- `81dd38e` fix: `collect()` dug its target directly, so `PROTECTED_AREAS` only stopped
  pathfinder-driven digging. A `mine`/`chop`/`shift` target inside a protected box is now skipped.
- `670468c` fix: `craft wooden_pickaxe` failed with "no matching recipe": the 2 sticks ate planks
  made for the pickaxe. Planks are now made last.

```
tools/ship-claude 81dd38e 670468c
```

Live results (local stage, bot6+bot7, area around -95 64 -10, outside the protected boxes):

- Both mined `stone` x24 in the same area: `claims.refused` 2 (bot6) and 5 (bot7), 0 timed out,
  0 pull-backs, no job error. Both ended with 24+ cobblestone.
- Worker bot5 against the lab hub (read-only): connected, logged in, spawned; lab `/api/state`
  showed `connected true, online true, host bandit`; after SIGINT `connected false, online false`,
  `lastSeen` 4 s old.

Owner's live check list for the already-shipped hub code: (1) shift with bot2+bot3 sharing an area
and watch the "reservations" line in the Debug panel; (2) a lab-dashboard job to bot5 while
`nix run .#mcbots-worker -- bot5` runs; (3) Ctrl-C the worker and see "offline, last seen ...".

## M2 - dashboard "what are they doing?": done

Commits (mcbots-only, no `docker-minecraft` restart): `81e7a10` backend (activity line, event ring
buffer + `GET /api/events`, queue removal, hash-based CSP), `6636334` the page, `cb1a326` docs and
screenshot (`docs/runbooks/minecraft/img/dashboard.png`, linked in `BOTS.md`).

```
tools/ship-claude 81dd38e 670468c 81e7a10 6636334 cb1a326
```

What is there: a card per bot (plain-language activity, progress bar, health/food, held tool with
durability, inventory + free slots, host, queue with remove), event log (ring buffer of 200, workers
forward theirs), map with claimed blocks and supply chest, job composer per bot and for a bot
selection (coordinates start at the supply chest), "Stop all", Debug panel kept under "Advanced".
`lastError` is cleared on respawn when it was "died"; other errors show their age and turn grey
after 5 min. The old page's `say` job stays available in the composer (I never sent one).

Live check (local stage, bot6+bot7): activity line, progress bars, durability (46/59 -> 16/59 of a
wooden pickaxe), claim-conflict event, queue with remove, map with claims; headless Chromium drove
the composer (open "Give a job", pick goto, coordinates prefilled from the supply chest, Run now ->
"sent: goto", Stop -> "sent: stop"). The strict CSP raised no console error. Full `nix flake
check` passed on the committed tree.

New tests: ring-buffer bound and ids, event cleaning, activity/tool/queue fields, hub field
sanitising, `remove` over the hub, `/api/events` and the CSP header through the real server.

## M3 - robustness for long runs: done

Commits: `744211b` (claims, hub offline/throttle), `5a502d3` (tool replacement, resume after
death, deposit when full, `place` job), fixes `77ea71c b70a63d 5e66231 d55a323`, docs `fe9907e`.

Live check (2026-10-09, local stage, bot6+bot7, `shift stone` into a chest at -104 68 -12,
`PROTECTED_AREAS` set, no `SUPPLY_CHEST`), 30 min without intervention:

- pull-backs 0 during the run (3 total, all at connect);
- claims: bot6 245 granted / 0 refused, bot7 138 / 2 refused, 0 timed out;
- bot6 replaced its pickaxe several times by itself and worked the whole 30 min;
- bot7 died once from a fall while digging down (-108 52 -15), respawned and walked back
  (resume works), but had lost its pickaxe and every tree was out of reach from the pit;
  with no supply chest on the stage the last fallback was missing, so the shift failed.
  On the lab `SUPPLY_CHEST` is set (re-arm after respawn). Open: avoid digging into drops.

## M4 - standing orders: done, not live-tested

Commits: `4b2922d` keeper, `c728558` dashboard panel, screenshot `f5f2759`. Unit-tested
in `app/test.js`. Not run live: the only supply chest (-37 65 -200) is at spawn where
players were. Off by default after a restart. Set `KEEPER_SITE` before switching it on
on the lab, otherwise the bots dig around the spawn chest.

## M5 - schematic building: skipped (design only, `6b18c15`)

## Ship

```
tools/ship-claude 81dd38e 670468c 6f894d0 81e7a10 6636334 cb1a326 8568526 744211b 5a502d3 4b2922d c728558 fe9907e 77ea71c 6b18c15 bd398b6 b70a63d 5e66231 d55a323 f5f2759 fb6e266 9438e51 <this commit>
```

## Waiting for the owner

- Ship (GPG + push).
- Choose a `KEEPER_SITE` before using standing orders on the lab.

## 2026-10-09 evening: control centre, settings, guard, torches

Live on the local stage: terrain map from BlueMap with click menus (`0cecb33`), in-game view
(`d6a2d1e`), settings + guard (`303c8a8`: a guarded zombie was hunted and killed, bot back at its
post), torches + ore search + review fixes (`147431c`: `mine iron_ore 8` gave 9 raw iron in
149 s with 7 wall torches). Lab bots work a resource site at -260 65 -213 (chest), diamond kit.

## To do (priority: P1 now, P2 next, P3 later)

- (done, `3b3b4a5`) P1 safe digging: never dig the block under the bot into a drop of more than 3 or into lava/water
  (bot7 fell to death, bots died to skeletons before the fight range).
- P1 kits: keep spare kits in the supply chest (axe and armour-from-inventory done).
  Lost kits today: bot1 x2 (skeletons), bot2, bot4 (drowned).
- (done, `0032d31`) P1 supply chest as a map marker that the owner moves.
- P2 precision everywhere (owner's wish: use what humans cannot time): instant tool swap per block
  (done), perfect crit/sweep timing (done), next: shield-free arrow dodging by side-stepping only
  when a skeleton draws, block-perfect bridging over gaps, MLG water bucket on falls, instant
  inventory sorting at the chest. No duplication glitches (they damage the shared world).
- AFK: bot4 stands at the owner's Nether-roof gold farm (167 234.5 603.5); after the deploy set its
  settings to defend off so it never walks off the roof.
- From the Jarvis plugin (iamgadgetman/jarvis, read 2026-10-09; Java/Citizens, so ideas only):
  (seal lava/water: done) P2 a full branch mine at a
  site marker (staircase, gallery, grid of branches, torch-lit); P2 guard leash + creeper first +
  remember attackers; later natural-language orders via a local model (stage 2) and builds as
  generated fill/setBlock scripts (stage 5). Done: junk thrown away during ore/log jobs.
  JARVIS-1 (CraftJarvis): research agent on 1.16 + GPU + OpenAI, not usable; only its
  recipe-tree planning with remembered plans maps to stage 2.
- P2 ore levels: send a bot to the ore's best Y first (diamond/redstone -59, gold -16, lapis 0,
  iron 16, copper 48, coal 96; 26.2 keeps the 1.18 distribution) and branch-mine there.
- P2 a cave layer on the map (top-down slice at the bot's height from its loaded blocks).
- P2 bulk crafting chains for the base (hoppers, rails, ...) and base quotas from the owner's list.
- P2 build job (schematic, design in BOTS.md).
- P3 crawl (trapdoor) 1x1 tunnels: mineflayer physics/pathfinder have no crawl pose; low value
  because bots see ores through stone and tunnel straight to them.
- Owner: `/vanish` (SModeration) already hides you, also on BlueMap; turn it on right after joining.

## Next (owner's goal: bots farm everything the automated base needs)

1. guard job (protect an area or a player); 2. safe branch mining at a set depth, no digging
into drops; 3. bulk crafting chains; 4. base quotas from the owner's materials list.
