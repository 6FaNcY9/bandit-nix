# GitHub Actions Workflows

This directory contains automated workflows for testing and validating the
NixOS configuration.

## Workflows

### 1. Test NixOS Configuration (`test-nixos-config.yml`)

**Triggers:** Push to `main`/`master`, pull requests, manual dispatch,
weekly schedule (Monday 06:00 UTC).

Jobs:

- **lint-commits** — Enforces conventional commit messages on PRs via
  `wagoid/commitlint-github-action`.
- **label-pr** — Auto-labels PRs by changed files using `actions/labeler`.
  Requires `.github/labeler.yml` to exist (currently a placeholder).
- **build** — Runs `nix flake check --no-build`, alejandra (`--check`),
  deadnix, statix, and builds the full system closure.
- **security-scan** — Scans the built closure with `vulnix` and uploads a
  JSON report as an artifact.
- **build-vm** — Builds and runs the NixOS VM test
  (`checks.x86_64-linux.bandit-test`) under KVM.
- **update-flake** — Manually triggered: updates `flake.lock` and opens a
  PR via `peter-evans/create-pull-request`.

### 2. Nightly Build Test (`nightly-build.yml`)

**Triggers:** Daily at 02:00 UTC, manual dispatch.

Updates all flake inputs, runs `nix flake check` and a full system build,
and only then commits/pushes the new `flake.lock`. This avoids publishing
a known-broken lock file to the default branch.

### 3. Auto Format Nix Files (`auto-format-nix.yml`)

**Triggers:** Push touching any `.nix` file, manual dispatch.

Runs `alejandra` over the tree and pushes a `style: auto-format nix files`
commit if anything changed. Uses a `concurrency` group so simultaneous
pushes serialise, and rebases onto the latest remote tip before pushing.

## Local Testing

```bash
# Validate flake (no build) — same as CI
nix flake check --no-update-lock-file --no-build

# Build the full system
nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
  --print-build-logs --no-update-lock-file --fallback

# Build and run the VM test (needs KVM)
nix build .#checks.x86_64-linux.bandit-test --print-build-logs --fallback

# Format / lint
nix run nixpkgs#alejandra -- .             # fix
nix run nixpkgs#alejandra -- --check .     # check only
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
```

## Troubleshooting

1. Check the job logs in the Actions tab.
2. For flake-check failures: review recent changes to `flake.nix` and
   imported modules.
3. For build failures: check package availability and version
   compatibility against `nixos-unstable`.
4. For VM test failures: inspect `tests/bandit.py` and the affected
   systemd units.
5. For formatting/lint failures: run the local commands above.
