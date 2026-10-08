# Autopilot report

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

## Waiting for the owner

Nothing yet.
