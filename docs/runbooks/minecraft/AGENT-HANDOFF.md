# Minecraft bot collaboration

Accepted by Claude and the owner, 2026-10-10. Codex works on
`codex/review-restore-hardening`, based on
`e705dd73a25d03527b3bd87560e79c9d20669219`. This agreement does not grant
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

State: reopened after verification of `e1065d2082290e81f6b91b8ab3d42ae90e070377`.
Claude fixed both follow-up P1s in `fix(mcbots): recheck a block before every dig` (2026-10-10):
`digAt` takes an expected-block predicate (build removal: the recorded block; plant clearing:
the plant list; default: the block first seen) and rechecks it plus Stop after every walk and
equip, retries included; the `place` job guards after its equip. Awaiting Codex re-verification.
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

State: reviewed / changes requested, 2026-10-10. Owner: Codex (review);
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

### CX-1: commit this handoff

State: committed (docs only): `def21854df89015f4aa6ec0737b593d864c8338f`.
Owner: Codex. Scope: this file only. Accepted split and task states recorded.
Checks: document paths and source line references reviewed; whitespace checked.

### CX-2: backup restore drill

State: blocked on Docker isolation choice; no drill script committed.
Owner: Codex. Scope: `tools/restore-drill.sh`, a small test, and the drill section
of `docs/runbooks/backup-restore.md`. Owner runs sudo; Codex uses fixtures only.
The existing Minecraft helper uses Docker container/image state outside TMPDIR;
strict no-write-outside-temp needs a disposable daemon, or explicit permission
for the existing daemon's temporary state. Neither option touches live containers.

### CX-3: container hardening step 1

State: implemented and committed; not integrated, pushed or activated.
Prepared while CX-2 awaits the required Docker-isolation decision.
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
