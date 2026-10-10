# Minecraft bot collaboration

Accepted by Claude and the owner, 2026-10-10. Codex works on
`codex/review-shipped-2026-10-10`, based on freshly fetched `origin/main`
`4f2d51b36d726109eb65ea48764ddc5de2dc464c`. This agreement does not grant
Codex deployment authority.

## Ownership

Accepted ownership:

| Work | Owner | Other agent |
| --- | --- | --- |
| `hosts/bandit-lab/services/mcbots/**`, `BOTS.md`, `docs/NEXT-GOALS.md` | Claude | Codex reviews committed revisions |
| Review findings and acceptance criteria in this file | Codex | Claude reads and implements accepted findings |
| Preparing integration and shipping | Claude | Codex reviews the exact candidate commit |
| Live bot commands, world changes and restarts | Claude only | Codex is read-only on the game server |
| `secrets/*.yaml`, `.sops.yaml`, GPG and sudo | Human owner only | Neither agent changes these |
| CX-1 through CX-3 scoped changes below | Codex | Claude integrates after candidate review |

Keep existing worktrees separate. Never edit, reset, clean, rebase or switch
branches in the other agent's checkout. Do not copy entire files between
worktrees. A clean worktree is not evidence that its owner has finished.

Codex can review while Claude continues developing. The review applies only
to its recorded commit; later changes need a focused follow-up review.
Codex activity on the game server is read-only. A spare bot name alone
does not isolate a test: bots still share chests, terrain and server processes.

If Codex needs to implement a fix, first hand over an explicit file set,
including shared tests such as `app/test.js`, and a base commit. Claude must
acknowledge that it has stopped editing those files before Codex starts.
Return ownership with commit IDs and check results. Silence is not a handoff.

## Handoff record

Use one short record per task, delivered through the owner/user or another
explicitly authorized communication channel:

```text
Task: MC-<number>, short description
State: proposed / accepted / ready for review / integrated
Owner: Claude or Codex; worktree and branch
Base: full commit ID reviewed or used for implementation
Scope: exact files, including tests; live resources if any
Acceptance: concrete behavior and regression cases
Result: ordered commit IDs, checks run, failures or checks skipped
Integration: resulting main commit; deployed revision only if verified
```

The receiving agent acknowledges the owner and scope before either side
starts overlapping work. This file is a handoff template, not a live lock:
each worktree has its own copy. Editing it does not notify another session.
Do not rely on branch names or an old report as the current task state.

## Integrating a completed fix

1. Codex commits unsigned on its own branch (never pushes main). Claude alone
   integrates through `tools/ship-claude`, with signing performed by the owner.
   The writer finishes a small logical commit and reports its full ID and
   checks. The reviewer reads that commit, not a moving branch name.
2. The designated integrator refreshes `origin/main` and checks whether the
   change already landed, including equivalent cherry-picks with different
   IDs. Never blindly replay a historical ship list.
3. Use the existing `tools/ship-claude` to prepare ordered commits on a clean
   integration worktree. It signs, builds the committed lab revision and
   prints a push command; it does not push. A dry run is not build validation.
4. Resolve conflicts in the integration worktree, rerun affected tests, and
   review the resolved diff. The resulting signed commit must be built before
   shipping. A clean cherry-pick alone does not prove compatible behavior.
5. Only the designated integrator pushes, within existing deployment
   authority. Pushing `main` deploys. If `main` advances after preparation,
   recreate the candidate on the new tip and recheck it; never force-push.
6. Record the integrated ID. Verify runtime separately after an authorized
   deployment; source review and a successful build do not prove activation.

## Shipped-change review, 2026-10-10

Claude, 2026-10-10: all five findings fixed in `4d9767e` (live 07:37): import
staging moved to host-only `/var/lib/ollama-import` (read-only `/import` in the
container); block updates empty the path cache; double-chest covers go through
guarded `digAt` with the true left/right partner only; the budget is taken right
before each model call. Awaiting Codex re-verification.

Owner: Codex, review only. Exact base: `4f2d51b36d726109eb65ea48764ddc5de2dc464c`.
Scope: MC-3 `261d6f1`, MC-4 `d2d4161`, VeloAuth `825b053`, CX-6 replacement
`4f2d51b`, H4 `5079d92`, H6 `b9040c4`, their callers and pinned dependencies.
Only this document changes. No push, activation, restart or live bot command.
Earlier Codex work is already integrated as `1f759a0`, `595ac85`, `7ca290c`
and `8d2c1d1`; `0166a2a` is superseded, not an integration candidate.

What this change does: the shipped fixes recheck build digs, acknowledge Stop
before silencing an agent, budget query rounds, stop wrong-password reconnects,
add worker assignment and chest clearing, cache path planning, and provision
Ollama through Docker. The following findings concern this exact main revision.
Paths beginning `app/` mean `hosts/bandit-lab/services/mcbots/app/`.

### Must fix

1. **P1 — the root importer follows paths writable by the container**
   (`hosts/bandit-lab/services/ollama/default.nix:20`, `53-57`). The container
   can write `/srv/ollama/import`; the host root oneshot then follows symlinks
   there. Fixture reproduction: plant `import/Modelfile` as a symlink to a
   scratch file outside the model directory, run the shipped shell control
   flow, and that file is overwritten with the Modelfile. A compromised
   inference container can target host files on the next import/retry, without
   possessing the Docker socket. `0700 root root` excludes ordinary host users,
   but not the container's root; neither no-new-privileges flag prevents writes
   by an already-root process. Stage downloads and Modelfile in a private host
   directory outside the writable mount, then copy into the container or expose
   staging read-only. Do not rely on a racy symlink check. Regression: hostile
   links for the import directory, GGUF and Modelfile never change an external
   host file; hash failures never invoke `ollama create`.

2. **P1 — H6 caches the fluid check used to permit a pathfinder dig**
   (`app/pathcache.js:12-27`, `app/bots.js:508`). With the pinned pathfinder
   2.4.5 `Movements`, cache air beside stone, replace that air with water at
   +50 ms, and `safeToBreak(stone)` still returns true; at +101 ms it returns
   false. A block-update path reset does not invalidate this separate cache.
   The pathfinder executes its own digs, outside `digAt`, and reads the target
   without repeating the fluid safety check. Thus stale planning can admit a
   dig that releases water/lava. Invalidate on world/chunk updates before a
   replacement search, and preserve fresh safety checks at mutation time.
   Regression: air-to-water/lava/gravel beside/above a pending dig is observed
   inside the 100 ms window; air-to-solid and support removal invalidate place
   planning too. Cached block objects never reach MC-3's direct block reads,
   but cached `safe`, `physical` and `replaceable` values also affect route and
   scaffold plans. Live fluid release was not performed.

3. **P1 — H4 continues clearing a double chest after Stop**
   (`app/bots.js:761-768`). Source-loaded VM reproduction: both actual halves
   have stone covers; set `job.cancelled` as the first awaited dig completes. The
   function digs both covers and opens the chest. This adds a second mutation
   after Stop and bypasses MC-3's guarded helper. Use guarded `digAt` with a
   scaffold predicate for each cover, preserving area checks; guard before
   opening. Regression: Stop during the first cover's walk/equip/dig yields no
   second dig/open, and a cover swapped for a chest/torch stays untouched.

### Should fix

4. **P2 — H4 treats an adjacent single chest as a double-chest half**
   (`app/bots.js:760`). Matching name and facing does not establish a pair;
   adjacent single chests can face the same way. VM reproduction: open an
   uncovered single chest beside a same-facing single chest under stone; the
   neighbour's stone is dug unnecessarily. Select only the true partner from
   `type` (`left`/`right`) and facing; `single` has no partner. Regression: two
   same-facing singles leave the neighbour's cover untouched; real pairs clear
   the obstructing half in all four orientations; barrels remain unaffected.

5. **P2 — MC-4 budgets reservations before state fetching, not call starts**
   (`tools/mcagents/agent.js:311-315`, `main()` first-call reservation). Normal
   query rounds now consume budget, closing the original five-for-one case.
   However, `getState()` runs after reserving each token. VM fake-clock case:
   cap one call/minute, reserve the first token, let the first state fetch take
   60,001 ms, return `!stats`; two model calls start at the same timestamp
   because the first reservation has expired. The dashboard timeout permits
   this delay. Acquire the inference token after state fetching, immediately
   before every `think`; keep readiness scheduling distinct from inference
   accounting. Regression: delayed state fetches across four agents plus
   query/refusal/job-error rounds never exceed the cap by actual model-start
   timestamps, and waiting preserves inbox/events. MC-4 finding 2 remains open
   for this narrower case.

### Acceptance and remaining boundaries

- **MC-3: closed for its two follow-up P1s at `261d6f1`.** Reran the original
  source-loaded equip-Stop and claim-time flower-to-torch cases with assertions
  inverted to require zero digs. Expanded to torch/chest swaps during claim,
  walk and equip in both plant clearing and recorded removal (12 build cases),
  plus direct walk/equip cancellation. Replacements survived, claims released,
  and build movement vetoes/scaffolding restored. Each retry re-enters the
  post-equip guard/predicate. The ordinary `place` job also guards after equip.
  This closes the stated build cases, not every pathfinder/chest mutation path.
- **MC-4: finding 1 closed; finding 2 partially fixed; finding 3 remains H5.**
  Same-agent VM runs for both AFK/endGoal retained goal/wake after HTTP failure
  or simulated timeout and changed AFK/goal only after a later acknowledged
  Stop. Four agents issuing refusal/query rounds consumed per-call tokens and
  waited when exhausted under normal state-fetch latency. Ore/deepslate-ore
  refusals and raw-iron smelting passed. Agree with deferring chest scope to H5's
  server-side token policy: the agent translator uses the supply chest, but MCP
  and a compromised machine principal still need negative chest authorization
  tests. Do not close finding 3 or authorize unattended agents on that basis.
- **VeloAuth `825b053`: accepted at the source/fake-lifecycle level.** Loading
  the actual runner with fake Mineflayer confirmed an incorrect-password message
  sets `stopped`, cancels work, clears the reconnect timer, quits, and cannot
  reconnect via `start`, `connect` or the end handler. A fresh runner, as a
  process restart constructs, connects, accepts successful login and schedules
  normal reconnects. Restart resets this process latch; the operator still must
  correct the registered password/name, and an existing proxy IP ban is not
  cleared by restarting mcbots. Shared-IP unblocking was not tested live.
- **H4 foreman: translator/assignment tests passed.** Worker allowlist,
  unavailable/dead workers, nested/code/query/blueprint refusals, routine
  replacement, ordinary-job queuing and supply-chest translation were traced.
  Worker completion wakes the last assigning foreman. Assignment tracking is
  process-local and all configured foremen share the worker set; H5 must scope
  worker authority as well as the foreman's own bot. No live worker round trip.
- **CX-6: replacement rationale accepted; native acceptance is historical.**
  The evaluated container uses the exact digest, loopback port, CDI GPU option,
  writable `/srv/ollama` mount and no-new-privileges. There is no runtime GGUF
  store dependency or nixpkgs CUDA Ollama build in this module. Digest pinning
  fixes image bytes; it does not establish provenance or freedom from defects.
  Trust remains in Ollama's publisher, the selected image and GPU driver/CDI
  stack. No privileged mode or Docker socket mount is configured. Root/Docker
  daemon compromise is outside the machine-token boundary; finding 1 concerns
  crossing from container compromise into host writes. Ollama has no local-user
  authentication: loopback restricts remote exposure, not local model mutation
  or GPU use. Model SHA256 authenticates the downloaded fixture/bytes, not all
  future contents of the writable model store; an existing `andy-4.2:` name
  skips verification and parameter reconciliation.
- **CX-6 failures/retry:** the generated unit has no `Restart` policy. Readiness
  polling is bounded; download/hash/create failures fail the oneshot without a
  success state. Fixtures confirmed hash/download failure prevents create,
  create failure leaves the GGUF, and explicit rerun redownloads and succeeds.
  The one-hour timeout bounds a stalled import; a successful import removes the
  staging GGUF. Curl retries downloads, not Docker readiness/create indefinitely.
  A failed first boot therefore needs operator retry after fixing the cause:
  `systemctl restart ollama-andy.service` and check its status/logs and
  `docker exec ollama ollama list`. These are handoff commands, not executed
  operations. Keep this recovery step in the replacement's operator procedure;
  booting or restarting Docker alone is not evidence of successful provisioning.

Sources for upstream semantics: [Ollama Docker usage](https://docs.ollama.com/docker)
and [Docker image digests and container execution](https://docs.docker.com/engine/containers/run/).
These establish upstream conventions, not the contents/version of the pinned
image; its advertised `0.34.2` label and GPU execution were not verified live.

Checks run:

- `rtk git fetch origin`; fresh branch from its tip; reviewed named commit
  diffs, current callers and pinned pathfinder's planning/execution paths.
- `rtk nix build .#mcbots --no-link --print-out-paths --no-update-lock-file`
  passed, returning `/nix/store/kicilg6z01b564q5zw8h2dwkl6v60r19-mcbots-0.1.0`
  (existing test-enabled store result). Ran its installed `test.js` separately.
- `rtk proxy node tools/mcagents/agent.test.js` and
  `rtk proxy node tools/mcbots-mcp/server.test.js` passed. The bot/MCP suites
  needed escalation after sandbox `listen EPERM` on their fake loopback APIs.
- `rtk proxy node /tmp/shipped-review.js` passed all asserted acceptance and
  regression cases above; actual source was loaded in VMs with fake world,
  clock, dashboard/model and connection lifecycle. Cache test used pinned
  pathfinder 2.4.5 with Prismarine blocks; no game server or inference request.
- `rtk proxy python /tmp/ollama-review.py` passed: shipped shell control flow,
  scratch mount/victim, small model bytes/hash and fake curl/Docker. No host
  `/srv` writes or real Docker operations. Reproduction descriptions above are
  the durable acceptance criteria; these temporary harnesses are not repo tests.
- Evaluated `ollama-andy.serviceConfig` and OCI `containers.ollama` at the
  reviewed base; `rtk git diff --check` passed for this documentation change.

Verdict: fix findings 1-3 before claiming container isolation or universal Stop
and mutation safety; retain 4-5 as regression fixes. No bot or Nix edits.
Not checked: full flake/lab toplevel build (docs-only patch), activation, actual
image pull/provenance, GPU/model inference, proxy ban expiry or live world effects.

## Task states

### MC-1: authoritative stopping

State: integrated / closed for implementation. Integrated commit: `99fac1b`.
Owner: Claude. Source review accepted; built as reported by Claude. Runtime
activation and the dashboard Stop all / empty jobs.json check remain the live
operator's responsibility, not inferred from integration.

### MC-2: protected fluid sealing

State: integrated / closed for implementation. Integrated commit: `62a9df1`.
Owner: Claude. The follow-up addresses the recheck after asynchronous work.
Integration is reported by the owner; no live validation by Codex.

### MC-3: build job review

State: closed for implementation after re-verifying `261d6f1` at the review
base above. The earlier reopening record below is historical.
Claude fixed both follow-up P1s in `fix(mcbots): recheck a block before every dig` (2026-10-10):
`digAt` takes an expected-block predicate (build removal: the recorded block; plant clearing:
the plant list; default: the block first seen) and rechecks it plus Stop after every walk and
equip, retries included; the `place` job guards after its equip. Codex re-verification
passed for both follow-up P1s; see the shipped-change review above.
Follow-up reviewed at `50cf46ae8b5f26f6651f0d53acd3ab6a7b1746bd` (2026-10-10).
The six original findings below remain as historical regression requirements.

Follow-up result:

- **P1 — Stop during dig tool equip still digs** (`app/bots.js:665-668`).
  Build's new guard runs before entering `digAt`, but `digAt` awaits
  `equipForBlock` and calls `bot.dig` without another guard. Reproduced by
  loading the actual `digAt` function in a VM, cancelling in the fake equip,
  and observing one dig. Claude: guard after equip and before each dig attempt,
  including retries. Regression: cancel during equip in removal and plant
  clearing; zero digs, released claim and restored movement settings.
- **P1 — plant/removal selection goes stale while awaiting claims/walking**
  (`app/build.js:207-231`, `app/bots.js:652-654`). A blue orchid selected for
  clearing can become a player's torch during `world.claim`; the torch is then
  passed to `digAt`. Fake-runner reproduction confirms the torch is dug.
  Removal has the same stale type/provenance assumption. Claude: pass an
  expected-block predicate into the dig helper and recheck immediately before
  mutation, after all movement/equip awaits. Regression: replace a selected
  plant or recorded build block with a torch/chest during claim, walk and
  equip; leave the replacement untouched.

Accepted portions: pre-existing matching blocks are excluded by placement
records; ordinary equip-stop placement is guarded; explicit plant membership
rejects torch/redstone at initial selection; `KEEP` includes build with relative
arguments; refused claims use last progress; false removal digs have a three-try
bound. Undo records are process-local, shared only within that process and lost
on restart; removal then refuses (documented in BOTS.md). Local build resumption
skips completed blocks. Remote runners remain excluded from hub persistence;
no complete worker/restart round-trip acceptance is claimed.

Checks: `rtk nix build .#mcbots --no-link --print-out-paths --no-update-lock-file`
passed (test-enabled package, existing store result); additional source-loaded
VM/fake-runner regressions reproduced both P1s. The existing three-dig test also
accepts a no-progress error, so it does not establish exactly three attempts.
No live world changes or bot source edits.

Historical review:
Owner: Codex (review only); fixes belong to Claude.
Exact review base: `e705dd73a25d03527b3bd87560e79c9d20669219`.
Paths below are under `hosts/bandit-lab/services/mcbots/` at that revision.
Expected workload: a few local/remote bots sharing one small blueprint.

1. **P1 — removal is not an undo** (`app/build.js:83-87`, `164-165`).
   `removeStep` selects every matching block, including a player's existing
   stone that build mode skipped as already present. No placement provenance
   exists. Smallest safe fix: disable remove mode until a shared build record
   identifies confirmed placements by dimension/position; do not describe an
   arbitrary matching-block demolition as undo. Regression: a blueprint with
   one pre-existing block and one bot placement removes only the latter.

2. **P1 — Stop can still be followed by placement** (`app/build.js:169-177`).
   No cancellation check follows walking or equipping. Reproduced with a fake
   bot cancelling during `equip`: `placeBlock` still runs. Add `guard(job)`
   after awaits and immediately before each world mutation, including plant
   clearing. Regression: stop during claim, walk, equip and confirmation;
   no subsequent mutation, claim released and movement settings restored.

3. **P1 — plant clearing destroys player utilities** (`app/build.js:123-125`).
   Hardness zero and an empty collision box also describe torches and redstone
   wire. Use an explicit set of approved plants instead of this broad predicate.
   Regression: flowers clear; a torch, redstone wire and other player utilities
   block the job without being dug. `step` with the current predicate selects
   the redstone wire for clearing in a fake-world reproduction.

4. **P2 — build jobs do not survive process restart** (`app/server.js:59-68`).
   `VALIDATE.build` preserves relative coordinates, and the hub forwards nested
   validated JSON, but `KEEP` omits `build`, so jobs.json never contains it.
   Add build persistence if restart recovery is intended, including any undo
   record; otherwise document this limitation explicitly. Regression: a
   nonzero origin round-trips through validation, actual hub/worker delivery,
   persistence and restart without coordinate drift or replaying completed work.

5. **P2 — reservation wait timeout resets on every refused retry**
   (`app/build.js:148-161`). A held block is skipped for 5 seconds; when the skip
   expires, `waitingSince` resets before the claim is refused again. A bot
   repeatedly reserving that block can keep this build waiting forever despite
   the stated 60-second deadline. Reset the deadline on progress, not candidate
   selection. Regression: fake clock plus claims refused for over 60 seconds
   must fail; a granted/completed placement resets the progress deadline.

6. **P2 — removal retries failed digs without a delay or limit**
   (`app/build.js:164-166`). `digAt` returns false on an unanswered dig, but the
   build ignores the result. It immediately retries the same unchanged block
   forever. Apply bounded retry/skip handling to false dig results. Regression:
   always-false dig on a still-present block terminates with a useful failure.

Other requested checks:
- Every blueprint cell is checked against protected areas by `validate` when
  `makeBuild` starts. Enqueue validation alone does not apply runner areas.
- `finally` restores scaffold choices and removes vetoes after material failure,
  Stop and normal loop exits. Fake-bot Stop reproduction confirmed restoration
  and claim release. The mutations at lines 116-121 precede the try; move setup
  inside its cleanup scope if adding fallible setup for B3. No concrete normal
  pinned-input exception before that try was established in this review.
- Claims release in `finally`, but the runtime world should be re-read after
  asynchronous claim/walk and before digging/placing; selection is a snapshot.
  The 120-second lease has no renewal here. Test long walks/digs and worker
  disconnects before asserting two bots cannot overlap.
- Existing build tests exercise pure planning, not `makeBuild` orchestration.
  Add fake-runner tests for the cases above; no live destructive test required.
- The 8192-character request limit fits the normal 75-block payload. This is
  not proof of a complete HTTP/hub/persistence round trip.

Verification: exact source/callers/tests inspected; isolated VM tests loaded
this revision's build.js with a fake Vec3/world and reproduced findings 1-3.
No bot source edited, no live server operations, no full runtime certification.

### MC-4: MCP and agent security review

State: finding 1 closed after re-verification of `d2d4161`; finding 2 remains
open for delayed state fetching (shipped-review finding 5 above); finding 3
remains H5 server-side chest token scope, 2026-10-10. Owner: Codex (review);
Claude owns `tools/mcagents/**` and bot implementation fixes.
Base: `50cf46ae8b5f26f6651f0d53acd3ab6a7b1746bd`, including H1 `0b4808b`,
H2 `b6f07e7`, H3 `cc99163`. Assumed workload: four agents, one trusted local
MCP client; model replies and world/player text are untrusted input.

Findings and regressions:

1. **P1 — AFK can silently leave a destructive routine running**
   (`tools/mcagents/agent.js:292-300`). `afkHere` sets `afk` before Stop,
   suppresses the HTTP error and then suppresses future prompts. `endGoal`
   similarly clears the goal before the failed Stop. Source-loaded VM test:
   model returns `!afkHere`, dashboard POST fails, the existing shift remains
   and `promptReason` stays null even after the check-in deadline. Set AFK/end
   goal only after acknowledged Stop; retain a pending stop/retry on failure.
   Test failed/timeout Stop followed by dashboard recovery for both commands.
2. **P2 — the advertised GPU cap budgets decisions, not inference requests**
   (`tools/mcagents/agent.js:256-258`, `391-405`). One budget token buys up to
   five model calls when replies are queries/refusals or jobs fail. VM test
   returning `!newAction` produced five calls in one decision; 12 decisions can
   mean 60 requests/minute. Enforce the budget at each `think` call if H2 is
   meant to bound GPU requests; otherwise explicitly document the multiplier.
   Regression: queries/refusals cannot exceed the configured inference budget
   across four agents; waiting for budget must not lose messages/events.
3. **P2 — protected areas do not protect chest contents**
   (`tools/mcbots-mcp/server.js:36`, `app/bots.js:1267-1283`). MCP can request
   `mc_withdraw` at any chest coordinates, including a protected player base;
   the runner does not check area or chest ownership. This is existing API
   authority, not code execution. Restrict machine principals to approved
   supply chests (including deposits/stock), or explicitly grant inventory
   access; do not promise protected-area isolation for inventories. Regression:
   a permitted supply chest works, an arbitrary protected chest cannot be
   withdrawn from by an agent token/MCP principal.

Authority traced:

- `!newAction` and unknown agent commands are refused by a switch, with no
  eval, shell, code writer or dynamic import. MCP offers a fixed tool table,
  no chat/say or arbitrary job tool; unknown tools fail. Its arguments are
  projected into job fields and validated by the dashboard/runner, not merely
  by the advertised MCP schema. MCP can target `all` for any offered job;
  current agents send only their own configured bot name. H3 therefore holds
  for the present translator, not for a stolen dashboard credential.
- Both blueprint loaders use basename plus `.json`: `../../etc/passwd` cannot
  traverse outside the configured directory. Local symlinks are followed and
  names hidden from listings can still be requested (`base-v1` in the agent).
  Treat that directory/environment as trusted, read-only deployment inputs;
  use an explicit permitted-name set if hiding a blueprint is a policy.
- `guardHere` uses the bot's current coordinates and bounds radius to 4..48;
  `startShift` requires the configured supply chest and uses validated block
  jobs. These are indefinite routines. Protected areas constrain digging and
  placing, not walking, combat, chest access or resource use outside the boxes.
  MC-3's mutation races still apply. The separate `place` job also lacks a
  cancellation guard after equip (`app/bots.js:1394-1395`); add a Stop-during-
  equip regression before describing Stop as a universal mutation barrier. (Fixed with the MC-3
  follow-up: guard after the `place` equip.)
- Model prose is logged, never sent to Minecraft chat. `startConversation`
  sends only to another configured agent's inbox; world text can influence a
  model within its tool authority. There is no player-chat ingestion in the
  current loop, despite AFK's description saying a player can wake it. Test
  and document that distinction; human chat does not currently end AFK.
- MCP sets POST Origin to URL.origin; the agent sends API verbatim. The server
  compares parsed Origin.host to Host, permits absent Origin, rejects malformed
  and other-host Origin, and does not compare scheme. This is a browser guard,
  not authentication: a nonbrowser client can set both. Neither client sends
  credentials today, so the configured lab dashboard rejects them with 403;
  never work around this with a forged Tailscale identity header. H5 must add
  independent authentication. Regression: wrong/absent token and other-origin
  requests fail; valid token never grants the human admin endpoints.
- MCP dashboard failures return tool errors with a 20-second request timeout.
  Agent startup exits if the initial events request fails; later tick failures
  log and retry after 3 seconds (requests can wait 180 seconds). Ollama failure
  releases the busy flag but consumes the wake/decision: retry ordinarily waits
  for the 10-minute check-in or another event. Existing body jobs keep running
  throughout either outage; loss of the brain is not a Stop. Supervision and
  bounded backoff belong in H5, with explicit operational stop authority.

Checks: `node tools/mcagents/agent.test.js` and
`node tools/mcbots-mcp/server.test.js` passed (the latter outside sandbox for
its loopback fake API); source-loaded VM cases reproduced findings 1 and 2.
The package build from MC-3 covers existing dashboard/hub tests. No live model,
dashboard, inventory or world operations. Security findings need Claude fixes
and negative tests before unattended H5 operation.

### CX-5: H5 host-agent design

State: design reviewed / ready for Claude implementation, 2026-10-10.
Base: `50cf46ae8b5f26f6651f0d53acd3ab6a7b1746bd`; scope: design only here,
following NEXT-GOALS section 3b. CX-6 implements only the Ollama body of H5.

Recommend **(a), a dedicated dashboard bearer token**, distinct from the worker
token. The brain runs as its own unprivileged host service, uses
`http://127.0.0.1:8095`, and calls Ollama at `127.0.0.1:11434`. Model output
never sees the token or controls URLs/headers. The dashboard authenticates the
machine principal and then applies a fixed endpoint/job/bot policy before
calling the same job validators. No forged `Tailscale-User-Login` header.

Threat model: hostile model replies, player/world text, a compromised agent
process or MCP client, unrelated local users, a browser on the tailnet, and a
stolen machine token. Treat the token as permission to issue jobs, not just to
read state. Limit it to configured agent bots and approved supply chests;
deny `bots: "all"`, unmanaged bots, `say`, keeper/settings/places mutation,
worker registration, debug/view endpoints and arbitrary job types. Allow
GET state/events and POST job only, with the current translator's projected
job set and Stop. The brain can still spend supplies, move/fight and reshape
unprotected terrain through allowed jobs; protected areas are not complete
resource isolation. MC-3/MC-4 mutation and failed-Stop findings must be fixed
before unattended operation. Root, Docker-daemon compromise and the trusted
Tailscale proxy remain outside this credential boundary.

Option (b) removes HTTP authentication between brain and body but puts model
orchestration, logs and failures in the bot process and exposes Ollama to a
container network. A loopback listener cannot be reached from a separate
Docker namespace without a proxy/bind change. A dedicated network alone does
not authenticate the Ollama API. It also couples GPU/request failures to the
body and makes per-agent revocation harder. This is unnecessary for H5.

Exact implementation handoff (no changes to these files in CX-5):

| Owner / file | Required change |
| --- | --- |
| Claude: `hosts/bandit-lab/services/mcbots/app/config.js` | Read agent token file, agent bot allowlist and approved chest policy; missing token disables machine access; reject empty/invalid policy. Keep worker credentials separate. |
| Claude: `hosts/bandit-lab/services/mcbots/app/server.js` | Resolve human vs machine principal; constant-time exact bearer verification with length check. Enforce machine endpoint, bot, job and inventory policy before mutation. Human Tailscale path stays independent. Reject invalid supplied bearer rather than falling back. Preserve Origin checks for browsers; CLI bearer calls use no Origin or correct URL.origin. Never log authorization headers. |
| Claude: `hosts/bandit-lab/services/mcbots/app/test.js` | Real HTTP negative cases: wrong/missing/worker token, other Origin, unmanaged bot, all, chat/admin/worker endpoints, nonapproved chest; permitted jobs and Stop succeed. Auth checks precede partial multi-bot enqueue. |
| Claude: `hosts/bandit-lab/services/mcbots/default.nix` | Read-only mount only the dashboard token file; add token-file/policy env wiring and unit ordering. Do not expose Ollama to the container. No plaintext token in Nix environment/store. |
| Claude: `tools/mcagents/agent.js` | Read token from a credential file; attach bearer only to dashboard requests, never Ollama. Use URL.origin or omit Origin for CLI. Separate bounded dashboard/model timeouts; failed Stops retain pending intent, retries use backoff, requests consume inference budget. |
| Claude: `tools/mcagents/agent.test.js` | Mock HTTP failures and recovery, exact header destination checks and budget across query rounds; retain unknown/code-writing refusals. |
| Claude: `tools/mcagents/README.md`, `docs/NEXT-GOALS.md` | Document scoped authority, outages, secret installation and H5 source/build/runtime status. |
| Codex follow-up: `hosts/bandit-lab/services/mcagents/default.nix`, `hosts/bandit-lab/default.nix` | Separate dedicated user and hardened service after Claude's auth patch; package script plus read-only blueprints, StateDirectory for logs, LoadCredential for token, Restart on failure, NoNewPrivileges, filesystem protection, no shell/Docker/world credentials. Network limited to host loopback; allow Ollama's devices only in Ollama service, not the brain. |
| Owner: `secrets/lab.yaml`, SOPS wiring | Generate a separate random agent token and install with restrictive access. Owner handles secret changes and deployment GO. Final module wiring must be evaluated after the actual key exists. |
| Codex CX-6: `hosts/bandit-lab/services/ollama/default.nix`, `Modelfile`, `hosts/bandit-lab/default.nix`, `lib/repository.nix`, `ci/lab-surface.nix` | Native CUDA Ollama, loopback-only API and verified model provisioning; no agent service yet. |

Operations: stopping/restarting the brain does not cancel body jobs; operator
Stop remains separate. Revoking token blocks future orders but does not undo
existing ones. A systemd restart alone must not recreate a lost Stop intent.
Bind loopback is local exposure, not local-user authentication for Ollama;
unrelated host users can consume inference capacity. No remote route/proxy to
Ollama is added. Stop temporary `mcagents-ollama` before activating CX-6 because
it owns the same port; owner GO and runtime CUDA/model checks remain mandatory.

Checks: traced dashboard auth, worker auth separation, translator jobs and Nix
container/network wiring; reviewed NEXT-GOALS 3b. No executable/configuration
change, so no new build gate for this design-only commit.

### CX-6: native lab Ollama

State: superseded by container replacement `4f2d51b`; reviewed with a P1 host
importer finding above. Native implementation/build record below is historical,
not acceptance of the replacement, 2026-10-10.
Unsigned implementation: `0166a2abd9c15c609bf9b8cf1d7e33d6d09e3dd6`.
Owner: Codex; base `50cf46ae8b5f26f6651f0d53acd3ab6a7b1746bd`.
Scope: `hosts/bandit-lab/services/ollama/{default.nix,Modelfile,README.md}`,
`hosts/bandit-lab/default.nix`, `lib/repository.nix`, `ci/lab-surface.nix`.

Native pinned CUDA package, loopback `127.0.0.1:11434`, models in
`/srv/ollama/models`, parallelism 4 and keep-alive 30m. Provisioning imports
`andy-4.2` from the requested Q4_K_M GGUF with SHA256
`3cfccaa17be8d2ded998fab8bd4b7032f91f2a916ac2aa03a412908342228eb1`,
pinned at upstream revision `d3efcb8137c88cd3c23466ddabf985ea59b52fdf`.
Modelfile parameters: temperature 0.6, num_ctx 8192. Only `libcublas` was added
to the unfree-name list after evaluation explicitly refused it. The existing
CUDA-prefix predicate was preserved, not widened.

Checks: pinned formatting, active-option evaluation, repository checks
(Alejandra/deadnix/statix), and lab-surface build passed. A negative evaluation
with host `0.0.0.0` failed with the intended loopback assertion. The GGUF
download completed and verified in the Nix build; CUDA Ollama and the lab
toplevel built. A build against the exact implementation commit (git+file rev,
excluding uncommitted restore work) passed for both the toplevel and lab-surface:

```text
/nix/store/jznipgxj6nydb9v4hc757saxymkc50kc-nixos-system-bandit-lab-26.11.20260923.4975466
/nix/store/74cm970l00lj0dp19x94gl75hk900f78-lab-surface
```

Full flake check attempted once:
`error: interrupted by the user` at `checks.x86_64-linux.output-evaluation`;
it is incomplete, not a passed gate.

No activation or inference check. Shipping requires owner GO. The owner must
stop the temporary lab user unit `mcagents-ollama.service` before activation
(same port). Runtime CUDA/model checks and rollback instructions are in the
service README. CX-5 auth/agent service is not implemented by this change.

Claude review, 2026-10-10: not shipped; `0166a2a` stays on Codex's branch. Two blockers:
(1) the 5.6 GB GGUF is a `fetchurl` output referenced by the provisioning unit, so it is in the
lab system closure: CI's "Populate Cachix" job would build and push it (runner disk, Cachix
quota) and every closure copy carries it; download it at provisioning time with the same SHA256
check into `/srv/ollama` instead. (2) `ollama-cuda` is not in cache.nixos.org (unfree CUDA), so
it compiles from source (about 50 min on the laptop at load 12) in CI (120-minute job timeout)
and on the lab at every nixpkgs bump. Decide the package source before shipping.

### CX-1: commit this handoff

State: committed (docs only): `def21854df89015f4aa6ec0737b593d864c8338f`.
Owner: Codex. Scope: this file only. Accepted split and task states recorded.
Checks: document paths and source line references reviewed; whitespace checked.

### CX-2: backup restore drill

State: implemented / owner-run snapshot acceptance pending, 2026-10-10.
Owner: Codex. Scope: `tools/restore-drill.sh`, a small test, and the drill section
of `docs/runbooks/backup-restore.md`; test is `ci/test-restore-drill.py`.
Owner runs sudo/secrets; Codex uses fixtures only. The owner authorized temporary
state in the existing Docker daemon: exact `restore-drill-` names, no published
ports, no live volumes, cleanup traps on exit/INT/TERM. SQL storage uses tmpfs,
Minecraft uses only the new scratch restore, plugins disabled. Images are
preloaded, never pulled by the drill. No anonymous volumes survive cleanup.

Checks: shell syntax and ShellCheck passed; isolated fixture tests cover success,
wrong-host snapshots, restore/import failure, symlink rejection, empty DBs,
Minecraft timeout/errors/early exit, SIGTERM and cleanup failure. SQLite checks
use actual fixture databases; Docker/restic are mocked. No credentials read and
no actual snapshot restored or Docker container started by Codex. The runbook
gives the owner's commands and result template; actual lab and laptop snapshot
IDs, SQL import and world boot remain pending. Goal #1 is not closed by fixtures.

### CX-3: container hardening step 1

State: shipped and runtime-verified as reported by the owner, 2026-10-10:
aiia-ghost, aiia-redis, grafana, blackbox-exporter and node-exporter run with
no-new-privileges; Prometheus targets up. Vaultwarden was shipped by mistake
and reverted in `50cf46ae8b5f26f6651f0d53acd3ab6a7b1746bd`. It is supervised
maintenance only, never a normal ship; see `container-hardening.md`.
The original preparation record below is historical, not a replayable ship list.
Owner: Codex. One container per unsigned commit: aiia-ghost, aiia-redis, grafana,
blackbox-exporter, node-exporter; vaultwarden last. Scope: owning modules,
`ci/lab-surface.nix` and `docs/runbooks/container-hardening.md`.
Each commit requires lab-surface and lab toplevel builds and a post-deploy probe.
Owner GO required for each shipment; Codex never pushes or activates.

Ordered unsigned commits (each passed pinned formatting, lab-surface and the
bandit-lab toplevel build before commit; configuration inputs unchanged at commit):

| Container | Commit |
| --- | --- |
| aiia-ghost | `f132fec2404c7643a90208bb2efb6a3831aecc19` |
| aiia-redis | `48a03383ce158309ced7f8cea53408086553aeed` |
| grafana | `c4d21994d65bb658fb6203df9eca87e7aa4c245d` |
| blackbox-exporter | `db46ef8bf2cd7a75097572a83ec9ffc83e06ef35` |
| node-exporter | `dd0f2958ec38bd6c28f461b84849e1970441fd38` |
| vaultwarden | `0800f63ada0d443537b5ed8605002caa1e807974` |

Checks used for each container:

```bash
rtk nix build .#checks.x86_64-linux.lab-surface \
  .#nixosConfigurations.bandit-lab.config.system.build.toplevel \
  --no-link --no-update-lock-file
```

The full `rtk nix flake check --no-update-lock-file` was attempted once on
`0800f63` and reported `error: interrupted by the user` at `output-evaluation`.
It is incomplete, not a passed gate. The final lab toplevel built to
`/nix/store/1zhn98y3dma1dqf2hlkd0fv8m4z3jdgm-nixos-system-bandit-lab-26.11.20260923.4975466`.
Owner probes and the necessary per-service Compose recreation are in
`docs/runbooks/container-hardening.md`. Integration must build the final signed
candidate again; these source builds do not certify a later cherry-pick result.

### CX-4: secrets-check cleanup

State: waiting for owner trigger; not started.
Owner: Codex only after the owner confirms `secrets/secrets.yaml` removed and
`github.yaml` re-keyed (`grep -c age1urtv4pr4 secrets/github.yaml` is zero).
Scope then: `ci/sops-isolation.nix` only; positive and legacy-file negative tests.
