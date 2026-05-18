# Copilot Cloud Agent Instructions for `6FaNcY9/bandit-nix`

## What this repository is
- Flake-based NixOS configuration for one host: `bandit`.
- Main entrypoint: `./flake.nix`.
- System modules: `./nixos/`.
- Host-specific config: `./hosts/bandit/`.
- Home Manager config: `./home/`.
- Secrets policy: `./.sops.yaml` and encrypted data in `./secrets/secrets.yaml`.

## Critical architecture facts
- `flake.nix` defines only `nixosConfigurations.bandit`.
- Host module imports are rooted at `./hosts/bandit`, `./nixos`, and `./home` (via Home Manager module wiring).
- Stylix wallpaper path is hard-coded in `nixos/core.nix` as `../hosts/bandit/wallpaper.jpg` — do not rename or remove this file without updating that path.
- `.sops.yaml` is at repository root (not inside `secrets/`).
- `nixos/default.nix` is the aggregator for all system modules — do not import individual `nixos/*.nix` files from `flake.nix` or `hosts/`.
- `home/default.nix` is the aggregator for all home-manager modules — it is loaded via `home-manager.users.vino = import ./home` in `flake.nix`.

## Flake inputs
| Input | Branch | Purpose |
|---|---|---|
| `nixpkgs` | `nixos-unstable` | Package set |
| `home-manager` | `master` | User environment management |
| `sops-nix` | default | Secrets management |
| `nixvim` | default | Neovim configuration in Nix |
| `stylix` | default | System-wide theming |
| `nixos-hardware` | default | Framework 13 AMD hardware optimizations |

All inputs use `inputs.nixpkgs.follows = "nixpkgs"` to avoid duplicate nixpkgs versions.

## Module ownership
| Concern | File |
|---|---|
| Bootloader / kernel / tmpfs | `nixos/boot.nix` |
| Locale / timezone / nix settings / GC / fonts / Stylix | `nixos/core.nix` |
| Network / firewall / DNS over TLS / bluetooth | `nixos/network.nix` |
| Audio / pipewire / wireplumber | `nixos/audio.nix` |
| Display manager / greetd / XFCE / i3 / dconf | `nixos/desktop.nix` |
| Users / groups / sudo / passwords | `nixos/users.nix` |
| Hardware / filesystems / kernel modules | `hosts/bandit/hardware.nix` |
| Hostname / stateVersion | `hosts/bandit/default.nix` |
| Shell / fish / CLI tools / abbreviations | `home/shell.nix` |
| Editor / nixvim / LSP / DAP / plugins | `home/editor.nix` |
| Git / GPG agent / delta / signing | `home/git.nix` |
| Stylix targets (home-manager level) | `home/theme.nix` |
| i3 keybindings / startup / gaps / floating | `home/desktop/i3.nix` |
| XFCE panel plugins | `home/desktop/xfce-panel.nix` |

## How to work efficiently

### 1. Scope changes to the right layer
- Host/hardware/hostname → `hosts/bandit/*`
- System services/packages/options → `nixos/*.nix`
- User shell/editor/git/desktop behavior → `home/*.nix` and `home/desktop/*.nix`

### 2. Prefer minimal module edits
- Keep module boundaries intact instead of moving options across files unless explicitly requested.
- Only add a new file when a concern is genuinely new — do not split existing files unless asked.

### 3. Keep formatting consistent
- Nix formatting is done with `alejandra`.
- Use 2-space indentation.
- Group related options under a single attrset rather than repeating the key prefix.
- Avoid repeated top-level keys in the same attrset (for example `services`, `users`, `programs`, `virtualisation`) to keep `statix` antipattern checks passing.

### 4. Preserve secrets workflow
- Never commit plaintext secrets.
- Keep encrypted values in `secrets/secrets.yaml`.
- Keep encryption rules in root `.sops.yaml`.
- The age public key is already configured in `.sops.yaml` — do not modify it.

## Important constants — do not change
```nix
system.stateVersion = "25.11"   # hosts/bandit/default.nix
home.stateVersion   = "25.11"   # home/default.nix
```
