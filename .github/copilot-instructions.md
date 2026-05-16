# Copilot Cloud Agent Instructions for `6FaNcY9/bandit-nix`

## What this repository is
- Flake-based NixOS configuration for one host: `bandit`.
- Main entrypoint: `/home/runner/work/bandit-nix/bandit-nix/flake.nix`.
- System modules: `/home/runner/work/bandit-nix/bandit-nix/nixos/`.
- Host-specific config: `/home/runner/work/bandit-nix/bandit-nix/hosts/bandit/`.
- Home Manager config: `/home/runner/work/bandit-nix/bandit-nix/home/`.
- Secrets policy: `/home/runner/work/bandit-nix/bandit-nix/.sops.yaml` and encrypted data in `/home/runner/work/bandit-nix/bandit-nix/secrets/secrets.yaml`.

## Critical architecture facts
- `flake.nix` defines only `nixosConfigurations.bandit`.
- Host module imports are rooted at `./hosts/bandit`, `./nixos`, and `./home` (via Home Manager module wiring).
- Stylix wallpaper path is hard-coded at `nixos/core.nix` as `../hosts/bandit/wallpaper.jpg`; do not rename/remove this file without updating that path.
- `.sops.yaml` is at repository root (not inside `secrets/`).

## How to work efficiently
1. **Scope changes to the right layer**
   - Host/hardware/hostname: `hosts/bandit/*`
   - System services/packages/options: `nixos/*.nix`
   - User shell/editor/git/desktop behavior: `home/*.nix` and `home/desktop/*.nix`
2. **Prefer minimal module edits**
   - Keep module boundaries intact instead of moving options across files unless requested.
3. **Keep formatting consistent**
   - Nix formatting is done with `alejandra`.
4. **Preserve secrets workflow**
   - Never commit plaintext secrets; keep encrypted values in `secrets/secrets.yaml` and rules in root `.sops.yaml`.

## Validation commands (match CI)
Run from repository root:

```bash
nix flake check --all-systems --no-update-lock-file
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --print-build-logs --fallback
nix build .#nixosConfigurations.bandit.config.system.build.vm --print-build-logs --fallback
nix run nixpkgs#alejandra --check .
```

## GitHub Actions behavior to keep in mind
- `test-nixos-config.yml` runs flake check, config build, and VM build/boot smoke test.
- `nightly-build.yml` updates flake inputs and builds to detect upstream breakage.
- `auto-format-nix.yml` auto-formats `.nix` files on push and commits formatting changes.

## Known pitfalls
- Breaking `hosts/bandit/wallpaper.jpg` path causes evaluation/build failures.
- README workflow docs may lag actual workflow YAML; trust `.github/workflows/*.yml` first.
- Changes to flake wiring can cascade into all CI jobs; keep them surgical.

## Errors encountered during onboarding and workaround
### Error
Running local validation commands in this cloud task environment failed with:

```text
bash: nix: command not found
```

### Workaround taken
- Confirmed canonical commands from workflow files under `.github/workflows/`.
- Documented those exact commands in this file for reuse.
- When `nix` is unavailable locally, use a Nix-enabled environment (or GitHub Actions) to execute full validation.
