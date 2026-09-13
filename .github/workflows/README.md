# GitHub Actions Workflows

This directory contains automated workflows for testing and validating the NixOS configuration.

## Test NixOS Configuration (`test-nixos-config.yml`)

**Triggers:** Push to main/master, Pull Requests, Manual dispatch, Weekly schedule (Monday 6am UTC)

### Jobs

- **lint-commits**: Enforces conventional commit messages on PRs.
- **label-pr**: Auto-labels PRs by changed files.
- **build**: Runs `nix flake check` (formatting, dead code, antipatterns, custom checks) and dry-run-evaluates the `bandit-ci` system closure.
- **build-vm**: Builds a QEMU VM of `bandit-ci` and runs a 90-second boot smoke test.
- **populate-cache**: On pushes to main and manual dispatch; builds the `bandit-lab` closure and pushes it to the `github-bandit-nix` Cachix cache (feeds the lab's hourly auto-apply). Needs the `CACHIX_AUTH_TOKEN` repository secret.
- **update-flake**: Manually triggered; updates `flake.lock` and opens a PR.

The vulnix CVE scan runs in GitLab CI (`.gitlab-ci.yml`), not here.

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
