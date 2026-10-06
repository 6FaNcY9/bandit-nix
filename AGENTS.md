# bandit-nix — Agent Guide

NixOS flake for `bandit` (Framework 13 AMD laptop) and `bandit-lab` (headless server), with Home Manager for `vino`.

## Working approach

- Inspect the current diff and relevant code before editing. Preserve unrelated user changes and keep the patch scoped to the requested task.
- Treat `flake.lock`, imported modules, and current host observations as evidence of versions and deployed state. Documentation can be stale; reconcile relevant conflicts without auditing the whole repository.
- Use `rg` and targeted reads. Read a referenced runbook only when its subject is relevant. Reuse evidence already gathered; repeat a check when inputs changed or a concrete uncertainty remains.
- Make routine, reversible implementation decisions autonomously. Respect the user's inspection-only, propose-first, no-restart, or no-deploy boundaries. Ask only for missing information or authority that materially blocks the next action.
- Finish with a concise summary of changes, checks and their outcomes, and any remaining blocker. Distinguish evaluated, built, activated, and runtime-verified results.

## Agent routing

- Routing is automatic: the main agent picks the cheapest capable route without the user naming a role. Follow the role definitions configured for the tool in use (Codex: `codex-usage-routes`; Claude Code: subagents). Consult them once when routing is needed; do not assume model names, prices, or capabilities from this file.
- The main agent handles small, bounded tasks directly, including targeted inspection, straightforward edits, documentation, and checks.
- Use `scout` for substantial exploration that benefits from a separate context. Use `worker` for a bounded implementation task when delegation is expected to reduce total effort. Do not require a scout-to-worker handoff for every edit.
- Use `architect` for a specific difficult design, security, migration, or debugging decision when cheaper investigation is insufficient. For a high-impact design decision, obtain that guidance before attempting a risky implementation.
- Delegate only when the expected benefit justifies startup, context, and coordination costs. Parallelize independent work; give writers distinct ownership. Never perform the same investigation in both parent and child.
- Give each delegated task its goal, relevant paths/evidence, scope, and expected output. Request concise findings with file references, decisions, checks, and blockers. Reuse an existing agent when its context remains relevant.
- If a configured role is unavailable, use an available capable route and briefly report any material limitation. Routing does not expand permissions.

## Repository entry points

| Concern | Start here |
| --- | --- |
| Inputs, outputs, formatter | `flake.nix`, `flake.lock` |
| Shared paths, username, theme, unfree policy | `lib/repository.nix` |
| Host configuration and hardware | `hosts/<host>/default.nix`, `hosts/<host>/hardware.nix` |
| Laptop system modules | `nixos/` |
| Headless server base | `nixos/server/` |
| Server services and assets | `hosts/bandit-lab/services/<name>/` |
| User environment | `home/` (`desktop/`, `terminal/`, `editor/`) |
| Secrets wiring and encrypted data | `nixos/sops.nix`, `.sops.yaml`, `secrets/` |
| Checks and CI | `ci/`, `.github/workflows/`, `.gitlab-ci.yml` |
| Operational procedures | `docs/runbooks/`; security roadmap: `docs/SECURITY-PLAN.md`; operator helpers: `tools/` |

Follow imports to establish what is active; a directory's presence does not mean its service is deployed.

## Nix conventions and project constraints

- Use the repository's pinned Alejandra formatter. Format changed Nix files; avoid unrelated repository-wide formatting.
- Extend the existing owning module. Keep `flake.nix` focused on host roots/aggregators and check definitions; avoid adding leaf configuration there.
- Reuse `lib/repository.nix` constants. Keep unfree packages scoped through `allowUnfreePredicate`; do not enable unfree packages globally.
- Preserve existing `system.stateVersion` and `home.stateVersion` unless an explicitly scoped migration requires changes. These values are not the installed NixOS release.
- Preserve independent nixvim pinning unless the task explicitly addresses dependency compatibility. Do not change `flake.lock` during unrelated work.
- Edit declarative sources rather than generated files under `/etc` or `~/.config`.
- Hyprland is owned by the system module; Home Manager configuration under `home/desktop/hyprland/` uses native Lua and structured bindings/rules. Preserve its `package = null` and `portalPackage = null` arrangement. Check local examples before editing.
- Preserve explicit Stylix target ownership; hand-maintained Hyprland, Rofi, and Mako settings must not gain conflicting generated settings.
- Keep PipeWire properties that require dotted names as literal keys (for example, `"default.clock.rate"`).
- bandit-lab opens firewall ports on `tailscale0` only. Docker-published container ports bypass the NixOS firewall, so every `ports` entry must bind `127.0.0.1` or the tailnet address (`repoConfig.lab.tailscaleIp`); the `lab-surface` flake check enforces it.
- Container privilege and deployment models differ between hosts. Inspect the affected host's modules and Compose definitions before changing them.

## Verification

Select checks based on the changed behavior and affected outputs. Preserve required CI gates; avoid repeating successful checks against unchanged inputs.

- Documentation-only changes: review accuracy, paths, examples, and the diff. Run relevant documentation checks if defined; a full Nix build is unnecessary unless executable/configuration content changed.
- Nix changes: format changed files and evaluate the affected configuration. Run relevant repository or service tests. Run the full flake check once before finalizing a configuration change, unless unavailable; report any skipped or blocked checks.
- Before deployment: build the affected output and follow its deployment/health procedure. Evaluation or a dry run alone does not establish runtime correctness.

Run from the repository root:

```bash
# Format only the changed Nix files (substitute actual paths)
nix fmt -- path/to/changed.nix

# Full flake checks; may build check derivations
nix flake check --no-update-lock-file

# Evaluate and preview the affected host's build plan; substitute the host
nix build .#nixosConfigurations.bandit-lab.config.system.build.toplevel --dry-run --no-update-lock-file

# Build without activating
nix build .#nixosConfigurations.bandit-lab.config.system.build.toplevel --no-link --no-update-lock-file
```

Inspect `flake.nix` for targeted checks and the `bandit-ci` configuration when host keys are unavailable. Diagnose SOPS errors from the actual message; do not assume every failure means a missing age key.

## Secrets and host operations

- Never commit or print plaintext credentials, decrypted secret files, private keys, or secret-bearing environment dumps. Use SOPS and existing secret delivery mechanisms; redact diagnostic output.
- Changes to `.sops.yaml` recipients require a recovery and re-encryption plan. Preserve host key provisioning and secret permissions.
- Confirm the target host before activation. `nixos-rebuild test` also changes the running system; it is not a read-only test.
- Respect deployment authority already granted by the task. A code edit alone does not authorize a restart, activation, disk operation, or service removal.
- Check `lab-update` and its current automation before publishing deployment-triggering changes. A push to a watched branch can trigger server activation; a no-deploy boundary includes that path.
- `lab-update apply` deploys fast-forwards only: a signed but older commit or rewritten history is refused (see `docs/runbooks/bandit-lab-updates.md`). `--allow-non-ff` is a manual override for a reviewed rewrite and must never appear in a systemd unit; the `lab-update` flake check enforces that.
- Preserve remote access, application data, volumes, and rollback options during host/service changes. Use the affected service's runbook and health checks; verify affected services after activation (`bandit-health` or `bandit-lab-health`, as appropriate).
- For Cloudflare routing, read `docs/runbooks/cloudflare-access.md`; reconcile remote configuration with the repository mirror.
- For encryption, installation, or recovery, read the relevant runbook and verify the actual disks/layout. Start with `docs/runbooks/bandit-luks-in-place.md` for laptop encryption. Never infer disk targets or migration status from historical notes.

## External research

Use local code and pinned inputs for repository facts. When external evidence is needed, prefer Firecrawl and primary/official sources. If Firecrawl is unavailable or cannot retrieve the needed source, use another available provider. Honor explicit user provider preferences. Keep research bounded to the unresolved question and distinguish upstream guidance from the version actually pinned here.
