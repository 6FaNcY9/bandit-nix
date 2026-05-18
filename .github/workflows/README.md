# GitHub Actions Workflows

This directory contains automated workflows for testing and validating the NixOS configuration.

## Workflows

### 1. Test NixOS Configuration (`test-nixos-config.yml`)

**Triggers:** Push to main/master, Pull Requests, Manual dispatch, Weekly schedule (Monday 6am UTC)

This workflow performs comprehensive testing of the NixOS configuration.

#### Jobs

- **lint-commits**: Enforces conventional commit messages on PRs.
- **label-pr**: Auto-labels PRs by changed files.
- **build**: Validates flake structure, checks formatting/dead code/antipatterns, and builds the full system closure.
- **security-scan**: Scans built packages for known CVEs using vulnix.
- **build-vm**: Builds a QEMU VM and runs a 60-second boot smoke test.
- **update-flake**: Manually triggered; updates `flake.lock` and opens a PR.

### 2. Nightly Build Test (`nightly-build.yml`)

**Triggers:** Daily at 2 AM UTC, Manual dispatch

- Updates all flake inputs to latest versions
- Rebuilds the configuration with updated dependencies
- Helps catch upstream breaking changes early

### 3. Auto Format Nix Files (`auto-format-nix.yml`)

**Triggers:** Push touching any `.nix` file, Manual dispatch

- Formats all Nix files using `alejandra`
- Commits formatting changes automatically if detected

## Local Testing

Run these from the repository root in a Nix-enabled environment:

```bash
nix flake check --no-update-lock-file
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --print-build-logs --no-update-lock-file --fallback
nix build .#nixosConfigurations.bandit.config.system.build.vm --print-build-logs --no-update-lock-file --fallback
```
