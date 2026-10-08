# Autopilot goal for the laptop Claude Code CLI

One long unattended run that develops and live-tests the bots on a branch.
Shipping to the lab stays with the owner (one `tools/ship-claude` per
milestone). Read `HANDOFF-2026-10-08.md` (state, root causes, environment) and
`OVERNIGHT-REPORT-2026-10-08.md` first. `OVERNIGHT-GOAL.md` is done.

## The owner's one-time setup

```bash
cd ~/src/bandit-nix && git fetch origin claude/cool-edison-4tqtx1
git worktree add ~/src/bandit-nix-auto -b claude/autopilot origin/claude/cool-edison-4tqtx1
bash ~/src/bandit-nix-auto/docs/runbooks/minecraft/handoff-memory/install.sh ~/src/bandit-nix
cd ~/src/bandit-nix-auto && claude
```

Answer the first permission prompts for `nix`, `git`, `node`, `curl` and
`ssh bandit-lab` with "don't ask again" (or start with
`claude --permission-mode auto` if available; never `bypassPermissions`). Then
paste the `/goal` line at the end. Nothing else is expected from the owner
until the report. Anything that truly needs the owner goes into the report
under "Waiting for the owner"; skip that item and continue.

## Allowed in this run

- Live tests with **local** bots on the laptop: a local stage
  (`node app/server.js` with `BOT_NAMES=bot6,bot7`, `MC_HOST=100.125.161.81`,
  dashboard on `127.0.0.1:8095`, its own local password seed; BotGate admits
  `botN` from the laptop) and laptop workers (`nix run .#mcbots-worker -- bot5`).
- Read-only use of the lab: `ssh bandit-lab` for logs/`docker ps`, and
  `GET` on the lab dashboard API
  (`https://bandit-lab.tail7facc9.ts.net:8445/api/state`, `/api/debug`).
- Bots may dig and place outside the protected areas
  (`-80,-144,80,80`, `112,368,272,592`). The `say` job and any chat output are
  forbidden.

## Hard rules

- Work only in `~/src/bandit-nix-auto` on branch `claude/autopilot`; push only
  that branch. **Never push to `main`** (it deploys to bandit-lab). Never touch
  `~/src/bandit-nix` (the owner's uncommitted `flake.lock`).
- Never: `nix flake update`, changes to `flake.lock`, `secrets/`, `.sops.yaml`,
  `sudo`, `nixos-rebuild`/`nrs`, `lab-update`, force push, history rewrite,
  service restarts, Tailscale/Cloudflare/firewall changes, `POST` to the lab
  dashboard (jobs for bot1..bot4 stay with the owner).
- Never print secrets (worker token, password seeds, auth keys).
- No subagents, no workflows. Debugging budget: 5 hypotheses / 45 minutes per
  bug, then document it in `BOTS.md` ("Troubleshooting") and move on.
- Owner's "Not now" list stays out: more than 4 lab bots, farm building,
  Baritone/Meteor, Cloudflare cleanup, a night-time deploy window.
- Movement stays: no sprint, no parkour, no diagonals (`safeMovements()`).
- If players are online near the test area (`/api/state` player list), move the
  test area or pause live tests.
- Gates before every commit: `nix fmt -- <changed .nix>`; `nix build .#mcbots
  --no-link --no-update-lock-file` (runs `app/test.js`) when `app/` changed;
  `lab-mcbots` and `lab-surface` checks when Nix changed. Unsigned commits
  (`git -c commit.gpgsign=false commit`), one topic each, pushed after every
  finished item. At the end of each milestone: full
  `nix flake check --no-update-lock-file` once.
- Every milestone ends "ready to ship": list its commit SHAs in the report as
  one `tools/ship-claude <sha> ...` line for the owner. Keep milestones to
  paths under `hosts/bandit-lab/services/mcbots/`, `tools/`, `docs/` (no
  `docker-minecraft` restart); anything else is listed separately.

## Milestones, in order

### M1 — ship list for what is already on the branch

Write the ship line for `9e750eb 68595ab 21db706` plus the docs commits and
the owner's live check list (shift with bot2+bot3 sharing an area, a lab job to
bot5, worker offline display). Then verify what can be verified locally: local
stage with bot6+bot7 mining in the same area shows `claims.refused` > 0 and no
block mined twice; a worker bot5 against the local stage hub is not possible
(the hub is the lab), so test the worker against the lab hub read-only only
(connect, spawn, `connected`/`lastSeen` in lab `/api/state` after SIGINT).

### M2 — dashboard: "what are they doing?" (owner's request)

The owner must understand at a glance what every bot does and manage them from
the page. Restructure `app/public/index.html` (dependency-free, no CDN, keep
the same-origin and CSP rules):
- one card per bot with a plain-language activity line ("mining iron_ore 12/32
  near -120 40 -30", "walking to the supply chest", "idle - no job",
  "dead - respawning"), job progress bar, queue, health/food, held tool and its
  durability, inventory summary, host (lab/laptop), online state;
- an event log (last ~200 events: job started/finished/failed, death, respawn,
  deposit, claim conflicts, hub connect/disconnect) from a bounded ring buffer,
  via the existing websocket or `GET /api/events`;
- a small top-down map (canvas) with bot positions, supply chest, protected
  areas and claimed blocks, no external tiles;
- management: job form with presets (mine/chop/shift/craft/smelt/goto/deposit,
  coordinates prefilled from the supply chest), per-bot stop/replace, "stop
  all", queue view with remove;
- the Debug panel stays as an advanced section;
- `lastError` clears (or is marked old) after respawn.
Tests for every new API field and the ring-buffer bounds. Live check on the
local stage, plus a screenshot (headless Chromium/Playwright if available)
saved under `docs/runbooks/minecraft/img/` and linked in `BOTS.md`.

### M3 — robustness for long runs

- tool breaks: craft or fetch a replacement pickaxe/axe and resume;
- hunger: eat from inventory or take food from the supply chest when food < 14;
- death: return to the job area and resume (job keeps its progress);
- full inventory in non-shift jobs: deposit at the supply chest, resume;
- prune expired claims so they stop counting towards the per-bot cap;
- hub: remove remote runners offline for more than 1 h; per-connection
  throttle where possible.
Live check on the local stage: a 30-minute `shift` with bot6+bot7 without
intervention: pull-backs ~0, no job failed for a reason M3 covers.

### M4 — standing orders (bots work on their own)

A "keeper" that keeps the supply chest stocked: quotas (defaults declared in
`default.nix`, e.g. logs 64, cobblestone 128, coal/charcoal 32, torches 64), a
bot reads the chest contents when it is there, the scheduler assigns jobs to
idle bots (lab and connected workers), the dashboard shows quotas, stock and
who works on what, with an on/off switch (default off after a restart). Live
check on the local stage for 30 minutes, then switch off.

### M5 — optional: schematic building (BOTS.md "later phase")

Design first in `BOTS.md` (blueprint format `[{x,y,z,block}]`, placement order,
scaffolding rules), then a `build` job with block claims and several bots.
Test builds at most 5x5x3, within 40 blocks of spawn, outside protected areas,
no player-made blocks within 10 blocks; remove the test build afterwards.

## Report

Keep `docs/runbooks/minecraft/AUTOPILOT-REPORT.md` (English, short) updated
after every milestone and push it: per milestone done / partial / blocked,
commits, the `tools/ship-claude ...` line, live check results with numbers,
"Waiting for the owner", ranked recommendations.

## `/goal` line

```
/goal Work through docs/runbooks/minecraft/AUTOPILOT-GOAL.md in worktree ~/src/bandit-nix-auto on branch claude/autopilot (never push main, no deploy). Done when M1-M4 are committed, pushed, live-tested on the local stage and listed ready-to-ship (or documented as blocked), M5 is done or explicitly skipped, and docs/runbooks/minecraft/AUTOPILOT-REPORT.md is pushed.
```
