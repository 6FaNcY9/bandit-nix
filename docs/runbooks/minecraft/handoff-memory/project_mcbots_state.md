---
name: mcbots-state-2026-10-08
description: State of the cooperative Minecraft resource bots (bandit-nix) after steps 0-4; read HANDOFF-2026-10-08.md for details
metadata:
  type: project
---

Steps 0-4 (connect, crafting/smelting/shift jobs, stuck-bot fix, debug panel,
hub for remote workers) are done and live on `main` (`2e5885a`) on bandit-lab.

**Why:** the owner wants cooperative resource bots (lab bots bot1..bot4 plus
laptop worker bot5 via the hub). Stuck bug root cause: Paper 26.2 rejects
movement whose AABB touches a block face with gap 0.0; fixed in
`app/physicsfix.js` (GAP = 1e-4).

**How to apply:** before touching mcbots code, read
`docs/runbooks/minecraft/HANDOFF-2026-10-08.md` (state, dead ends, hub protocol,
shipping) and `AUTOPILOT-GOAL.md` (current work list; overnight run done, see OVERNIGHT-REPORT). Not yet verified live:
job from lab dashboard to bot5, shared reservations with several bots, offline /
last-seen display. Not now: >4 lab bots, farm building, Baritone/Meteor,
Cloudflare cleanup, night deploy window.
