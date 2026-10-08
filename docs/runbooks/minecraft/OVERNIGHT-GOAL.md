# Overnight goal for the laptop Claude Code CLI

Self-contained task for an unattended run. Read `HANDOFF-2026-10-08.md` first
(state, root causes, shipping, environment). This file only adds the rules and
the work list for the night.

## Hard rules (a violation means: stop and write it into the report)

- Work only on the branch `claude/overnight-2026-10-08`, created from
  `origin/claude/cool-edison-4tqtx1`, in a **separate worktree**
  (`git worktree add ~/src/bandit-nix-night -b claude/overnight-2026-10-08 origin/claude/cool-edison-4tqtx1`).
  Never touch `~/src/bandit-nix` itself: it carries the owner's uncommitted
  `flake.lock`.
- Never push to `main`. Pushing `main` deploys to bandit-lab within the hour. Only
  `git push origin claude/overnight-2026-10-08` is allowed.
- Never run `nix flake update`, never change `flake.lock`, `secrets/`, `.sops.yaml`.
- No `sudo`, no `nixos-rebuild`/`nrs`, no `lab-update`, no service restarts, no
  writing `ssh bandit-lab` commands (read-only `ssh bandit-lab` is fine).
- Nothing in game: no dig, place, chat, no bot jobs on the lab dashboard. A
  movement-only experiment with a throw-away test account is allowed only for
  task 6 and only if the lab is idle (no players online; check `/api/state`).
- Never print or write secrets (token, auth keys, decrypted files).
- Commits are unsigned (`git -c commit.gpgsign=false commit`); the owner re-signs
  when cherry-picking for a ship. Do not use the owner's GPG key.
- No subagents, no workflows. Usage is limited: read targeted, do not re-run
  successful checks on unchanged inputs.
- Debugging budget: 5 hypotheses / 45 minutes per problem; then write findings
  into the report and move on.
- Before **each** commit: `nix fmt -- <changed .nix files>`, then
  `nix build .#mcbots --no-link --no-update-lock-file` (runs `app/test.js`) when
  anything under `app/` changed, then the affected flake check. English commit
  messages, one topic per commit.

## Work list, in this order

1. **Full `nix flake check --no-update-lock-file`** from the worktree. Expected:
   all green; `security-lab-atomic` was only blocked by the cloud sandbox. Fix
   real failures that belong to the bots code; report others.
2. **Flakiness loop for `app/test.js`**: run it 20 times (`NODE_PATH=<mcbots
   out>/lib/node_modules/mcbots/node_modules node test.js`). Any failure: find
   the timing assumption and replace it by polling with a deadline (as already
   done for "job after stop"). A flaky test fails a lab deploy, so this matters.
3. **Security review of `app/hub.js` and `app/hubclient.js`**: token check,
   frame size and rate limits, takeover on reconnect, input sanitising,
   resource exhaustion (many sockets, many claims, huge `observe`). Write a
   failing test for each real problem, then fix it. Report non-problems with the
   reason in one line each.
4. **`tools/ship-claude`**: a tested script for the shipping procedure in the
   handoff (clean worktree on `origin/main`, `cherry-pick -S`, signature check,
   build the committed revision, print the exact `git push` line and stop).
   It never pushes by itself. Test against temp repos (a bare "origin" with a
   `main` branch) with `--dry-run`; add a flake check or a shell test if the
   repo has a pattern for it. Document it in `BOTS.md`.
5. **Hub counters in `/api/debug` and the debug panel**: claims granted /
   refused / timed out per bot (and per worker), so reservations can be shown
   without a curl loop. Unit tests in `app/test.js`; keep `cleanDebug` strict.
6. **Optional, only if everything above is done**: ceiling flush experiment
   (vertical collision against a block above the head) with raw packets and a
   test account, movement only. Record the result in `BOTS.md`; do not change Y
   handling in `physicsfix.js` without a measured failure.

Skip anything already in the handoff's "Not now" list.

## Output

Push the branch regularly (after each finished task). At the end write
`docs/runbooks/minecraft/OVERNIGHT-REPORT-2026-10-08.md` (English, short): per
task done / not done, checks run with results, commits (sha + subject), open
questions for the owner, and a ranked recommendation list. Commit and push it
last. Do not open a pull request.

## `/goal` condition (paste into the CLI)

```
/goal Work through docs/runbooks/minecraft/OVERNIGHT-GOAL.md on branch claude/overnight-2026-10-08 (separate worktree, never main, no flake.lock/secrets, no sudo/restart/deploy). Done when tasks 1-5 are committed and pushed to that branch with passing gates (or documented as blocked) and docs/runbooks/minecraft/OVERNIGHT-REPORT-2026-10-08.md is pushed.
```
