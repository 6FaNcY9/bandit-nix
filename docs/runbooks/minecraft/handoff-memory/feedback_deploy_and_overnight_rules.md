---
name: owner-working-rules
description: How the owner wants Claude to work on bandit-nix: language, report style, deploy and secret boundaries, unattended runs
metadata:
  type: feedback
---

Reply in German, short and plain; code and docs stay English. End every report
with a short ranked list of recommendations. One step at a time, report before
the next.

**Why:** the owner is an IT student (security, performance), works with limited
Claude usage, and wants to set goals while Claude decides the technical details.

**How to apply:** never push to `main` (it auto-deploys); work on branches. Never
touch `flake.lock`, `secrets/`, `.sops.yaml`; never print secrets or auth keys.
Ask only for SOPS values, sudo on bandit-lab, a short in-game action, or a ship
step on the laptop. No subagents/workflows unless asked. Debugging budget: 5
hypotheses / 45 minutes per bug, then document in `BOTS.md` and stop. Never write
diagnostic text into game chat. Unattended runs: own branch + separate worktree,
no sudo/restart/deploy, unsigned commits, final report file.
