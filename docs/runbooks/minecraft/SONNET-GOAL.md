# Goal for a Sonnet session: bots build from materials they gathered

Written 2026-10-10 by the Opus session that shipped the `build` job (`e705dd7`). The design
decisions below are already made; follow them instead of redesigning. If something here turns
out to be wrong, stop at that step and report what you found and why (rule 9 below).

## The goal in one sentence

The owner sends one `build` job to one bot that starts with an empty inventory and an empty supply
chest, and the structure ends up placed from blocks that bot gathered itself. This is milestone B4
in `docs/NEXT-GOALS.md`. Ship B3 first, then B4, each as its own shipped commit.

## Read first (only these)

1. `AGENTS.md` and `CLAUDE.md` (deploy and secret rules).
2. `docs/runbooks/minecraft/BOTS.md`, sections "Building", "Jobs", "Long runs", "Shipping to the lab".
3. `hosts/bandit-lab/services/mcbots/app/build.js` (all of it, ~200 lines).
4. In `app/bots.js`: `child()`, `JOBS.withdraw`, `JOBS.mine`, `JOBS.smelt`, and
   `const build = buildJob.makeBuild(...)`.
5. In `app/test.js`: the block `// ---- build job ...` (copy its fake-world style).

## Rules (each one cost someone an hour before)

1. **Work in a detached worktree from `origin/main`**, never in `~/src/bandit-nix` (the owner's
   uncommitted work lives there):
   `git -C ~/src/bandit-nix fetch && git -C ~/src/bandit-nix worktree add --detach ~/src/bandit-nix-b3 origin/main`.
2. **Files you own:** `hosts/bandit-lab/services/mcbots/**`, `docs/runbooks/minecraft/BOTS.md`,
   `docs/NEXT-GOALS.md`. Codex may be editing `docs/runbooks/minecraft/AGENT-HANDOFF.md`,
   `tools/restore-drill*`, `ci/sops-isolation.nix`, `ci/lab-surface.nix` and the aiia, monitoring
   and vaultwarden modules. Do not touch those. Never touch `secrets/` or `.sops.yaml`.
3. **Nix only sees files git knows about.** After creating a new file, run `git add -N <file>`,
   otherwise `nix build` fails with `MODULE_NOT_FOUND`.
4. **Tests run inside the package build:** `nix build .#mcbots --no-link --no-update-lock-file`
   runs `app/test.js`. If it prints a store path, the tests passed.
5. **Pushing `main` deploys the lab within the hour.** A mcbots-only change restarts the bots,
   not Minecraft, so it is allowed. Before pushing: `git fetch`. If `main` moved (another agent
   pushes too), `git rebase --gpg-sign origin/main` and rebuild. Then build the committed revision
   (`R=$(git rev-parse HEAD)`):
   `nix build "git+file://$PWD?rev=$R#mcbots" "git+file://$PWD?rev=$R#checks.x86_64-linux.lab-mcbots" "git+file://$PWD?rev=$R#checks.x86_64-linux.lab-surface" "git+file://$PWD?rev=$R#nixosConfigurations.bandit-lab.config.system.build.toplevel" --no-link --no-update-lock-file`.
   Push with `git push origin HEAD:main` and confirm the output contains `HEAD -> main`
   (a rejected push once looked like success). Never force-push. Do not run a full
   `nix flake check`; it gets killed.
6. **Commits are signed** (`git commit -S`) and end with the `Co-Authored-By` line from the
   session's attribution rules. If GPG asks for a passphrase, stop and ask the owner to unlock it.
7. **zsh:** write `${R}` before a colon. `$R:h...` is a zsh modifier and silently mangles paths.
8. **Temporary files go in the session scratchpad**, not `/tmp`. A laptop shutdown wipes `/tmp`
   and kills a running local stage.
9. **Stop and report instead of guessing** when: a design decision here proves wrong, a test fails
   twice for a reason you cannot explain, a live bot does something destructive (digs a player
   build, dies twice), or the work needs sudo, GPG, secrets or an in-game action by the owner.
   For a hard design question, ask the `architect` subagent one narrow question. Tell the owner
   in one line before you launch it.
10. **Never `pkill -f`** with a pattern that matches your own shell. Stop the stage by its task or PID.

## How to work each milestone (do not skip steps)

1. Write a 5-line plan: files, functions, the new test cases, the live check, what "done" means.
2. Pure logic first: a function with no `bot` in it, tested with plain objects in `test.js`.
3. Wire it into the job. Keep `bots.js` changes small; the logic lives in `build.js`.
4. `nix build .#mcbots` until green.
5. Live check on the local stage (below). Record the numbers: seconds, counts, pull-backs, claims.
6. Re-read your whole diff once, as a reviewer. For every new `await`: what happens on Stop
   (`guard(job)`), on death, on a thrown error? Is everything you changed restored in `finally`?
7. Update `BOTS.md` "Building" with what is now true and the live numbers. Mark the milestone in
   `docs/NEXT-GOALS.md`.
8. Commit, build the committed revision, push (rule 5). Report to the owner in plain words: what
   bots can do now, what you tested, what is not done.

## Local stage (live test against the real server, bot6)

```bash
S=<your scratchpad>; mkdir -p $S/mcstate
P=$(nix build .#mcbots --no-link --print-out-paths --no-update-lock-file)
BOT_NAMES=bot6 MC_HOST=100.125.161.81 STATE_DIR=$S/mcstate \
  PROTECTED_AREAS="-80,-144,80,80;112,368,272,592" BLUEMAP_URL= SUPPLY_CHEST=<x,y,z> \
  $P/bin/mcbots > $S/mcbots.log 2>&1      # run in the background
```

Helpers (dashboard on `127.0.0.1:8095`; POSTs need both headers):

```bash
j(){ curl -s -X POST 127.0.0.1:8095/api/job -H 'Content-Type: application/json' -H 'Origin: http://127.0.0.1:8095' -d "$1"; echo; }
idle(){ timeout $1 bash -c 'until curl -s 127.0.0.1:8095/api/state | jq -e ".bots[0] | (.online and .job == null and (.queue|length)==0)" >/dev/null; do sleep 3; done'; }
curl -s 127.0.0.1:8095/api/state | jq -c '.bots[0] | {pos, inventory, lastError}'
curl -s '127.0.0.1:8095/api/events?since=0' | jq -r '.events[-6:][] | .text'
curl -s 127.0.0.1:8095/api/debug | jq -c '.bots[0] | {corrections, claims}'
```

- Test spot: the 3x3 pad at origin `-121 77 9` (y 77 is one above the ground there), west of
  the protected spawn box, in an area earlier bot tests dug. bot6's own crafting table stands at
  `-123 79 5`. Keep tests within ~20 blocks of that pad and remove what you build (`remove: true`).
- For a supply chest on the stage: `j '{"bots":["bot6"],"type":"place","args":{"item":"chest","x":-116,"y":77,"z":9}}'`,
  then restart the stage with `SUPPLY_CHEST=-116,77,9` (or the y the chest really has; check
  the "placed chest at ..." event). Leave it in place for the next session.
- Never use `say` or chat for checks; read `/api/state` and the events.
- A restarted stage resumes saved jobs: delete `$S/mcstate/jobs.json` before restarting if you
  do not want that.

## B3: build takes missing material from the supply chest

Design (decided): inside `build()` in `build.js`, where `missing material` is thrown today, try
the supply chest first.

- Change `shortfall(need, have)` to return the missing counts `{name: count}`. Add
  `formatShortfall(missing)` that returns `['2 stone', ...]` and use it for the error text.
- `makeBuild` gets a new dependency `withdraw(r, job, item, count)`. In `bots.js` it is
  `(r, job, item, count) => JOBS.withdraw(r, child(job, {type: 'withdraw', args: {item, count, ...r.supplyChest}}))`.
- In `build()`, when not in remove mode and something is missing and `r.supplyChest` is set: for
  each missing item, call `withdraw` for exactly the missing count. Catch "no <item> in the chest"
  per item and carry on, then count the inventory again. If anything is still missing, throw
  `missing material: <list> (not in the supply chest either)`. Call `guard(job)` between items.
- Do not withdraw more than missing, and never in remove mode.
- Tests (pure): `shortfall` returns counts; `formatShortfall` text; the "withdraw only what is
  missing" calculation, with `have` before and after.
- Live: put 9 cobblestone in the stage chest (`deposit` with `only: cobblestone`), empty bot6 of
  cobblestone the same way, then build the pad. Done when the pad is placed and the chest holds
  9 fewer. Then remove the pad.

## B4: the builder gathers what is still missing (the owner's goal)

Design (decided): the building bot gathers for itself. No keeper coupling, so it works with one
bot.

- In `build.js` add a pure `GATHER` table, item -> a list of `[jobType, args]` for the count `n`:
  - `cobblestone`: `[['mine', {block: 'stone', count: n}]]`
  - `dirt`: `[['mine', {block: 'dirt', count: n}]]`
  - `stone`: `[['mine', {block: 'stone', count: n}], ['smelt', {item: 'cobblestone', count: n}]]`
    plus, only when the bot has neither, `['mine', {block: 'coal_ore', count: ceil(n / 8)}]` before
    the smelt (it fails with `not enough fuel` without coal, charcoal, planks or logs) and 8 extra
    stone for a furnace when none is within reach. Read `smelt()` and `station()` in
    `crafting.js` first to confirm how the furnace is made.

  Anything else is "cannot gather <item> yet". Logs and planks are left out on purpose: `chop`
  takes any log type, so plank types would not match the blueprint.
- Add a pure `gatherPlan(missing)` -> `{jobs: [...], unknown: [...]}`. Test it.
- `makeBuild` gets `runJob(r, job, type, args)`. In `bots.js` it is
  `(r, job, type, args) => JOBS[type](r, child(job, {type, args}))`.
- Order in `build()`: B3 withdraw, then if still missing and `unknown` is empty, run the gather
  jobs in order, then recount and check again. Gather at most 2x the blueprint's block count in
  total (a guard against loops). Fail with `cannot gather <list> yet` before gathering anything
  when `unknown` is not empty.
- The `mine` job moves the bot away, so the place loop walks back on its own (`GoalPlaceBlock`),
  which is fine. While gathering, the build's box veto and the scaffolding filter are already
  active. Keep it that way: they are set before the material check.
- Tests: `gatherPlan` for each listed item, the unknown case, and the 2x cap.
- Live: bot6 with no cobblestone, chest without cobblestone, `build` the pad. **Done when** the
  pad stands from cobblestone bot6 mined during that job (events show `mine stone` inside the
  build). Then remove it. Write the result into `docs/NEXT-GOALS.md` B4 and `BOTS.md`, then tell
  the owner the goal is reached and what limits remain.

## Known traps (found live)

- The pathfinder spends cobblestone and dirt as scaffolding on ordinary walks, so inventory counts
  drop between jobs. The build job already removes its own block types from `scafoldingBlocks`
  (sic, mineflayer-pathfinder 2.4.5 spells it that way) during the job.
- `bot.placeBlock` on 26.x may not echo the update; the job polls `blockAt` for up to 2 s. Keep it.
- Sprint, parkour and diagonal moves make Paper pull the bot back, so they are switched off.
  Do not switch them on.
- A cell already holding the right block counts as placed. A pad can "finish" instantly when
  scaffolding happens to match; check the inventory difference, not only "finished".
- Flowers and grass in a target cell are broken first; any other block there fails the job
  ("X is in the way"). That is intended: it never breaks player blocks.
- The bot leaves crafting tables where it crafted tools. That is known and harmless at the test spot.

## After B4 (do not start without the owner)

B5 (schematic import, bigger builds, several builders) needs a design decision: scaffolding above
height 3, and layer claims. Write a short proposal and ask the `architect` subagent to review it
before writing code.
