# GitHub Actions Workflows

This directory contains automated workflows for testing and validating the NixOS configuration.

## Workflows

### 1. Test NixOS Configuration (`test-nixos-config.yml`)

**Triggers:** Push to main/master, Pull Requests, Manual dispatch, Weekly schedule (Monday 6am UTC)

This workflow performs comprehensive testing of the NixOS configuration:

#### Jobs

- **lint-commits**: Enforces conventional commit messages on PRs
- **label-pr**: Auto-labels PRs by changed files
- **build**: Validates flake structure, checks formatting, dead code, antipatterns, and builds the full system closure
- **security-scan**: Scans built packages for known CVEs using vulnix
- **build-vm**: Builds a QEMU VM and runs a 60-second boot smoke test
- **update-flake**: Manually triggered — updates `flake.lock` and opens a PR

### 2. Nightly Build Test (`nightly-build.yml`)

**Triggers:** Daily at 2 AM UTC, Manual dispatch

- Updates all flake inputs to their latest versions
- Rebuilds the configuration with updated dependencies
- Helps catch breaking changes from upstream early
- Commits updated `flake.lock` back to the repository

### 3. Auto Format Nix Files (`auto-format-nix.yml`)

**Triggers:** Push touching any `.nix` file, Manual dispatch

- Formats all Nix files using `alejandra`
- Commits formatting changes automatically if any are detected
- Runs after push so formatting is always consistent in the repository

## Performance Optimizations

All workflows use:
- **DeterminateSystems/nix-installer-action**: Fast, reliable Nix installation with flakes enabled
- **Official NixOS binary cache**: Pre-built nixpkgs paths via `cache.nixos.org`

## Expected Behavior

✅ **Success**: All jobs complete successfully, indicating:
- Flake evaluates correctly with no errors
- System configuration builds without errors
- No dead code or antipatterns detected
- Code follows alejandra formatting standards
- VM can be created and boots successfully

❌ **Failure**: One or more jobs fail, indicating:
- Syntax errors in Nix files
- Invalid package references or broken dependencies
- Configuration errors preventing system build
- Dead code or formatting inconsistencies

## Troubleshooting

If a workflow fails:

1. Check the job logs in the Actions tab
2. For flake check failures: Review recent changes to `flake.nix`
3. For build failures: Check package availability and version compatibility
4. For VM failures: Review boot configuration and system services
5. For formatting failures: Run `nix run nixpkgs#alejandra -- .` locally to fix
6. For dead code failures: Run `nix run nixpkgs#deadnix -- --fail .` locally
7. For antipattern failures: Run `nix run nixpkgs#statix -- check .` locally

## Local Testing

Run these from the repository root in a Nix-enabled environment:

```bash
# Check flake evaluation
nix flake check --no-update-lock-file

# Build full system configuration
nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
  --print-build-logs \
  --no-update-lock-file \
  --fallback

# Build VM
nix build .#nixosConfigurations.bandit.config.system.build.vm \
  --print-build-logs \
  --no-update-lock-file \
  --fallback

# Run VM locally
./result/bin/run-bandit-vm

# Format all nix files (fixes in place)
nix run nixpkgs#alejandra -- .

# Check formatting without fixing
nix run nixpkgs#alejandra -- --check .

# Check for dead code
nix run nixpkgs#deadnix -- --fail .

# Check for antipatterns
nix run nixpkgs#statix -- check .- Runs automatically to ensure the config stays up-to-date

## Performance Optimizations

Both workflows use:
- **DeterminateSystems/nix-installer-action**: Fast, reliable Nix installation
- **DeterminateSystems/magic-nix-cache-action**: Automatic caching of Nix store paths
  - Significantly reduces build times on subsequent runs
  - Shares cache between workflow runs

## Manual Triggers

All workflows can be manually triggered via the Actions tab using the "workflow_dispatch" event.

## Expected Behavior

✅ **Success**: All jobs complete successfully, indicating:
- Flake is valid and evaluates correctly
- System configuration builds without errors
- VM can be created and boots successfully
- Code follows formatting standards

❌ **Failure**: One or more jobs fail, indicating:
- Syntax errors in Nix files
- Invalid package references or broken dependencies
- Configuration errors preventing system build
- Formatting inconsistencies

## Troubleshooting

If a workflow fails:

1. Check the job logs in the Actions tab
2. For flake check failures: Review recent changes to `flake.nix`
3. For build failures: Check package availability and version compatibility
4. For VM failures: Review boot configuration and system services
5. For formatting failures: Run `nix run nixpkgs#alejandra -- .` locally to fix

## Local Testing

You can run the same checks locally:

```bash
# Check flake
nix flake check

# Build configuration
nix build .#nixosConfigurations.bandit.config.system.build.toplevel

# Build VM
nix build .#nixosConfigurations.bandit.config.system.build.vm

# Run VM
./result/bin/run-bandit-vm

# Format code
nix run nixpkgs#alejandra -- .
```
