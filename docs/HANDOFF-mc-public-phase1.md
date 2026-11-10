# Handoff: public Minecraft world, phase 1 (2026-11-10)

Working note for the session on the NixOS laptop. It lives on the branch `mc-public-phase1`
only: delete it before the branch is merged.

## Where things stand

The owner wants a public, free-to-join anarchy Minecraft world next to the private one,
with paid supporter extras later. The design was accepted on 2026-11-10 (host: lab container
plus VPS relay). Phase 1 (whitelisted testers over the tailnet) is written and pushed on a
branch in each repository:

| Repository | Branch | Commit | Base |
| --- | --- | --- | --- |
| bandit-craft | `mc-public-phase1` | `6ed03ef` | `main` at `e7503d2` |
| bandit-nix | `mc-public-phase1` | `4a9b71a` plus this note | `main` at `983753a` |

**Nothing was formatted, evaluated, built, signed or deployed.** It was written on a Windows
PC without Nix, by imitation of existing code. Treat every line as unproven until the
checks below pass. `main` is untouched in both repositories.

Read first, in this order:

1. `AGENTS.md` in both repositories.
2. bandit-craft `docs/specs/2026-11-10-public-anarchy-world.md`: the design and its reasons.
3. bandit-craft `docs/runbooks/minecraft/PUBLIC.md`: bring-up and runtime checks.
4. The code: bandit-craft `hosts/bandit-lab/services/minecraft-public/default.nix`,
   bandit-nix `hosts/bandit-lab/services/mc-public/default.nix` and `ci/lab-mc-public.nix`.

## What to do on the laptop

Fetch and switch to `mc-public-phase1` in both checkouts. `CRAFT` below is the path of the
bandit-craft checkout.

1. bandit-craft, format the changed files:

   ```bash
   nix fmt -- flake.nix hosts/bandit-lab/services/minecraft/plugins.nix hosts/bandit-lab/services/minecraft/nix-minecraft.nix hosts/bandit-lab/services/minecraft-public/default.nix
   ```

2. bandit-craft, check the Chunky pin. The hash in `plugins.nix` was taken from Modrinth's
   API and never fetched against; this must print the same hash:

   ```bash
   nix store prefetch-file --hash-type sha512 https://cdn.modrinth.com/data/fALzjamp/versions/RBuKjN4k/Chunky-Paper-1.5.66.jar
   ```

3. bandit-craft:

   ```bash
   nix flake check
   ```

4. bandit-nix, format the changed files:

   ```bash
   nix fmt -- hosts/bandit-lab/services/mc-public/default.nix ci/lab-mc-public.nix ci/lab-jerry.nix hosts/bandit-lab/default.nix flake.nix
   ```

5. bandit-nix, the affected checks. The pinned bandit-craft lacks the new module, so the
   branch evaluates only with the override (and without `--no-update-lock-file`):

   ```bash
   nix build --no-link --override-input bandit-craft "git+file://$CRAFT" .#checks.x86_64-linux.lab-mc-public .#checks.x86_64-linux.lab-jerry .#checks.x86_64-linux.lab-minecraft .#checks.x86_64-linux.lab-surface .#checks.x86_64-linux.repository
   ```

6. bandit-nix, the host build and then the full check:

   ```bash
   nix build --no-link --override-input bandit-craft "git+file://$CRAFT" .#nixosConfigurations.bandit-lab.config.system.build.toplevel
   ```

   ```bash
   nix flake check --override-input bandit-craft "git+file://$CRAFT"
   ```

Fix what fails on the branches. Do not weaken `lab-surface` or `lab-minecraft` to make
something pass: they must hold unchanged.

## Expected failures and unverified points

- `repository` (alejandra, deadnix, statix) is the likeliest first failure: the layout is by
  imitation only.
- `sops-isolation` fails until the owner adds `mc-public-tailscale-authkey` to
  `secrets/lab.yaml`. The key and the module must land in the same commit.
- Lines marked `UNVERIFIED` in the code and in `PUBLIC.md`:
  - whether nix-minecraft's units and the NixOS firewall run inside a user-namespaced
    container (`mc-public/default.nix`, the comment above `config`);
  - the empty `[forced-hosts]` table in the public `velocity.toml`;
  - the Paper key names in `paper-global.yml` and `paper-world-defaults.yml` (from
    docs.papermc.io, not from the pinned Paper 26.2 build 130). A wrong name breaks
    nothing, but that guard is then not in force;
  - SModeration without LuckPerms, one world border per dimension, Chunky's command names.
- `ci/lab-mc-public.nix` reads several nix-minecraft option paths (`environment`,
  `EnvironmentFile`, `managementSystem`, `files`). They were read from the pinned sources
  on GitHub, not evaluated.
- The veth drops sit in Docker's `DOCKER-USER` chain, as for jerry-box. They are only in
  force while Docker hooks that chain into `FORWARD`; runbook check 3 is the proof.

## Deviations from the jerry-box pattern (deliberate)

- The host refuse rule is inserted first in `nixos-fw` (`-I nixos-fw 1`), so it precedes the
  mcbots bridge accept. There is no accept for the host's tailscaled.
- Two extra `DOCKER-USER` rules: a drop to the mcbots bridge `10.250.77.0/29`, and a drop of
  new connections forwarded into the veth.
- The caps sit on `container@mc-public` as a whole. `TasksMax=2048` and `IOWeight=50` were
  picked without a measurement.
- The world is a bind mount: `/srv/mc-public/data` on the host, `/srv/minecraft` inside.
  User namespace base 589824, veth 10.251.1.1 and 10.251.1.2.
- `ops.json` is reset to `[]` on every start. `max-world-size=5000` caps the border; the
  visible border is a console step in the runbook.

## Boundaries

- Pushing to bandit-nix `main` deploys to the lab and would start the container. Do not
  merge or push to `main` in either repository without the owner's explicit go.
- Merge order when the owner decides: bandit-craft first (inert on its own), then
  `tools/craft-bump` in bandit-nix, then this branch rebased on `main`. The other order
  leaves `main` unable to evaluate.
- The two branch commits are unsigned (no signing key on the Windows PC). They must be
  re-signed on the laptop before they can reach `main`: `lab-update` deploys signed
  fast-forwards only.
- Owner only: the tailnet tag, grant and auth key; the sops entry; signing; deploying;
  every runtime check in `PUBLIC.md`. Never print the auth key or a decrypted secret.

## Open after phase 1 is green

- Not implemented: the random far spawn on first join and bedless death, and `difficulty`
  (Paper's default applies). Both need a decision before testers judge the gameplay.
- Phase 2: VPS relay with PROXY protocol, backups and a restore drill, a load test.
- Phase 3: whitelist off, chat guards, the store, legal pages.

## Decisions and plans that are not in the code

Owner decisions still open:

- the server name and domain;
- the named adult who answers chat reports within 48 hours;
- business registration and an adult Tebex account before the first sale;
- ordering the relay VPS.

Agreed with the owner in the session that wrote this:

- No operator or admin rights are sold, and nothing that gives a competitive advantage.
  Sold: supporter prefix and name colour, founder tag, Discord role, server-wide community
  goals. Payment through Tebex.
- Marketing stays inside Mojang's usage guidelines and is not aimed at children: no loot
  boxes, no pressure timers, no bought votes.
- Marketing sequence: no advertising in phases 1 and 2 (10 to 20 personally invited testers
  who get the founder tag); before opening, a Discord and a simple site with the address,
  the three rules, the "not an official Minecraft product" disclaimer and the legal texts;
  at opening, the large server lists and the server subreddits; afterwards short clips of
  real raids and bases, a monthly community goal and an open cost report.
- Estimates: fixed cost about EUR 8 to 9 per month plus EUR 3 to 5 electricity; break-even
  at 3 to 4 supporters. With 20 slots this covers costs; it is not an income.
