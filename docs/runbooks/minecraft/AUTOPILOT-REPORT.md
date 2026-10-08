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

## Waiting for the owner

Nothing yet.
