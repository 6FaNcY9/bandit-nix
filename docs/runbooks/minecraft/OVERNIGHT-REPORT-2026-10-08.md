# Overnight report 2026-10-08

Branch `claude/overnight-2026-10-08` (worktree `~/src/bandit-nix-night`). No main push,
no `flake.lock`/secrets change, no sudo/deploy/restart, nothing in game. Commits are unsigned.

## Tasks

| # | Task | Result |
| --- | --- | --- |
| 1 | Full `nix flake check --no-update-lock-file` | Done: "all checks passed!" (incl. `security-lab-atomic`). |
| 2 | `app/test.js` flakiness loop | Done: 0 failures in 20 runs on the original tests, 0 in 8 more after the new tests. Nothing to fix. |
| 3 | Security review `hub.js` / `hubclient.js` | Done, 3 real problems fixed with tests (below). |
| 4 | `tools/ship-claude` | Done, with `tools/ship-claude.test.sh` (temp repos, `--dry-run`), documented in `BOTS.md`. Signing and the build path are not exercised by the test (they need the owner's GPG key). |
| 5 | Hub counters in `/api/debug` + panel | Done: `claims {granted, refused, timedOut}` per bot, `workers` summary per host, "reservations" line in the panel. |
| 6 | Ceiling flush experiment | Not done (optional; needs a live account and an idle lab). |

## Task 3 findings

Fixed:
- A replaced worker connection could still `claim`/`release` for the bot it lost until its socket closed. Now the names are removed from the old connection on takeover.
- Authenticated sockets were uncapped (each costs memory before `hello`). Now max 24, then 503.
- No frame rate limit. Now max 200 frames/s per connection, then close 1008.

Not problems (token holder is the trust boundary, tailnet only):
- Token check: sha256 + `timingSafeEqual`, bearer format checked before hashing.
- Frame size: `maxPayload` 256 KB on the hub; binary/non-JSON frames close the socket.
- Sanitising: `cleanSnapshot`/`cleanDebug`/`cleanArgs` cap and type everything; `__proto__` keys are harmless via `Object.fromEntries`.
- Claims: key regex, 8 per bot, only for names in the hello, never lab bots.
- `observe`: per-frame caps (200 mobs, 100 blocks, 200 gone) and world-model caps.
- Slow reader: no pong for 30 s means terminate.

Accepted / noted:
- The failed-auth throttle is global: someone on the tailnet with a wrong token can lock out the real worker for a minute (429). Per-address throttling needs the proxied address, which Serve does not give reliably.
- A token holder can fill the 16 remote-bot name slots (runners are never removed) and can flood fake mobs to evict real ones. Rotate the token if that is suspected.
- Expired claims stay in the map until released/overwritten and count toward the 8-per-bot cap.

## Commits

- `9e750eb` fix(mcbots): harden hub against stale sockets and floods
- `68595ab` feat(tools): ship-claude prepares a signed, built ship and prints the push line
- `21db706` feat(mcbots): claim counters in /api/debug and the debug panel
- (this report)

## Checks run

`nix build .#mcbots` (runs `test.js`) before commits 1 and 3, `lab-mcbots` flake check, `shellcheck` on both tools, `tools/ship-claude.test.sh`. Full flake check was run once at the start; the final tree was not re-checked in full (only app/tools/docs changed).

## Open questions for the owner

- bot2/bot3 (dashboard screenshot): they show `last error: died` from 10 and 30 min ago, are idle, queue empty, 0 pull-backs. That is not a fault; they need a job (a deposit chest is a job argument, not a setting).
- Should `lastError` clear on respawn, so a stale "died" does not look like a current error?

## Recommendations (ranked)

1. Send a mine/work-shift job with the deposit chest coordinates to bot2/bot3 and watch the new "reservations" line.
2. Finish the live hub verification (dashboard job to bot5, two bots mining, offline display).
3. Ship commits `9e750eb` and `21db706` with `tools/ship-claude` (mcbots-only, no player disconnect).
4. Clear `lastError` after a respawn.
5. Per-claim expiry pruning in `WorldModel`.
6. Ceiling flush experiment, only with a measured failure.
