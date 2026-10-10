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

State: reviewed — changes requested before B3 integration.
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
