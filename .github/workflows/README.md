# GitHub Actions Workflows

This directory contains automated workflows for testing and validating the NixOS configuration.

## Workflows

### 1. Test NixOS Configuration (`test-nixos-config.yml`)

**Triggers:** Push to main/master, Pull Requests, Manual dispatch

This workflow performs comprehensive testing of the NixOS configuration with four parallel jobs:

#### Jobs:

- **check-flake**: Validates the flake structure and checks for errors
  - Runs `nix flake check` to ensure the flake is properly formatted and all outputs are valid

- **build-config**: Builds the complete NixOS system configuration
  - Builds the full system closure using `nix build`
  - Verifies all packages and configurations can be built successfully
  - Uses Nix caching to speed up subsequent builds

- **build-vm**: Creates and tests a VM image
  - Builds a QEMU VM of the NixOS configuration
  - Performs a quick boot test to ensure the VM can start
  - Useful for catching boot-time issues without needing physical hardware

- **check-formatting**: Validates Nix code formatting
  - Checks if Nix files follow standard formatting conventions
  - Uses `alejandra` or `nixpkgs-fmt` formatter

### 2. Nightly Build Test (`nightly-build.yml`)

**Triggers:** Daily at 2 AM UTC, Manual dispatch

This workflow tests the configuration with the latest upstream updates:

- Updates all flake inputs to their latest versions
- Rebuilds the configuration with updated dependencies
- Helps catch breaking changes from upstream early
- Runs automatically to ensure the config stays up-to-date

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
