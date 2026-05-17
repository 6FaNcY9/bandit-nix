# GitHub Actions Workflows

This directory contains automated workflows for testing and validating the NixOS configuration.

## Workflows

### 1. Test NixOS Configuration (`test-nixos-config.yml`)

**Triggers:** Push to main/master, Pull Requests, Manual dispatch, Weekly schedule (Monday 6am UTC)

#### Jobs

- **lint-commits**: Enforces conventional commit messages on PRs
- **label-pr**: Auto-labels PRs by changed files
- **build**: Runs flake evaluation without building checks, formatting/dead code/antipattern checks, and system build
- **security-scan**: Scans built packages for known CVEs using vulnix
- **build-vm**: KVM-enabled job that builds the VM test check (`checks.x86_64-linux.bandit-test`)
- **update-flake**: Manually triggered — updates `flake.lock` and opens a PR

### 2. Nightly Build Test (`nightly-build.yml`)

**Triggers:** Daily at 2 AM UTC, Manual dispatch

- Updates all flake inputs to their latest versions
- Validates updated lockfile with `nix flake check --no-build --no-update-lock-file`
- Builds the full NixOS system closure with updated inputs
- Commits and pushes `flake.lock` only when it changed

### 3. Auto Format Nix Files (`auto-format-nix.yml`)

**Triggers:** Push touching any `.nix` file, Manual dispatch

- Formats all Nix files using `alejandra`
- Commits formatting changes automatically when staged changes exist
- Rebases before push to reduce push races

## Local Testing

Run these from the repository root in a Nix-enabled environment:

```bash
# Check flake evaluation (without building checks)
nix flake check --no-build --no-update-lock-file

# Build full system configuration
nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
  --print-build-logs \
  --no-update-lock-file \
  --fallback

# Build VM test check (same target as CI build-vm job)
nix build .#checks.x86_64-linux.bandit-test \
  --print-build-logs \
  --no-update-lock-file \
  --fallback

# Format all nix files (fixes in place)
nix run nixpkgs#alejandra -- .

# Check formatting without fixing
nix run nixpkgs#alejandra -- --check .

# Check for dead code (excluding NixOS module false positives in nixos/users.nix)
find . \
  \( -path './.git' -o -path './.direnv' -o -path './result*' \) -prune -o \
  -type f -name '*.nix' \
  ! -path './nixos/users.nix' \
  -print0 | xargs -0 nix run nixpkgs#deadnix -- --fail

# Check for antipatterns
nix run nixpkgs#statix -- check .
```
