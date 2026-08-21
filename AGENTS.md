# bandit-nix — Agent Guide

This is the personal NixOS configuration flake for two hosts:

- **`bandit`** — A Framework 13 laptop with an AMD Ryzen 7040 chipset, used as a daily driver.
- **`bandit-lab`** — A headless homelab server.

The repo is a Nix Flake built on `nixos-unstable`. It declares NixOS system configurations, a standalone Home Manager configuration for the user `vino`, and CI checks.

## 1. Technology Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| OS | NixOS 25.11 (`nixos-unstable`) | Declarative Linux system |
| User env | Home Manager (master) | User dotfiles, packages, and services |
| Editor | nixvim | Declarative Neovim configuration with LSP, DAP, cmp, etc. |
| Theming | Stylix + custom base16 schemes | System-wide and Home Manager color/font/cursor theming |
| Secrets | sops-nix with age | Encrypted secrets at runtime via `/var/lib/sops-nix/key.txt` |
| Hardware | nixos-hardware | Framework 13 AMD 7040 optimizations |
| Window manager | Hyprland (Wayland) | Desktop compositor on `bandit` |
| Bars/notifications | Waybar / Mako | Status bar and notification daemon |
| Launcher | Rofi (Wayland build via `pkgs.rofi`) | Application launcher |
| Terminals | Kitty | Primary terminal emulator |
| Shells | Fish + Zsh | Both are enabled and share aliases from `home/terminal/aliases.nix` |
| Version control | Git + GPG signing | Commit signing and GitHub CLI |
| Containers | Rootless Docker + Podman | Dev tooling on `bandit`; Docker-backed services on `bandit-lab` |
| Server services | Traefik, Cloudflared, Tailscale, Samba, PostgreSQL, Ollama, Vaultwarden, Portainer, Cockpit | Homelab stack on `bandit-lab` |

### Key Inputs (see `flake.nix`)

- `nixpkgs` → `github:nixos/nixpkgs/nixos-unstable`
- `home-manager` → `github:nix-community/home-manager/master` (`follows nixpkgs`)
- `sops-nix` → `github:Mic92/sops-nix` (`follows nixpkgs`)
- `stylix` → `github:nix-community/stylix` (`follows nixpkgs`)
- `nixos-hardware` → `github:NixOS/nixos-hardware` (`follows nixpkgs`)
- `nixvim` → pinned independently (upstream recommends **not** using `follows`)
- `fzf-tab-source`, `pdfreader-nvim` → plain git inputs used as plugin sources

## 2. Repository Layout

```text
.
├── flake.nix                 # Entry point: inputs, outputs, CI checks, formatter
├── flake.lock                # Pinned dependency graph
├── lib/repository.nix        # Shared constants: username, paths, theme, unfree policy
├── pkgs/                     # Vendored packages (e.g. anisette-v3-server; the NUR
│                             #   package pinned a stale dub dependency hash)
├── hosts/                    # Host-specific hardware + host-level config
│   ├── bandit/
│   │   ├── default.nix       # Hostname, stateVersion, GRUB, kernel params
│   │   └── hardware.nix      # Filesystems, kernel modules, Framework tweaks (LUKS layout planned; see docs/runbooks/bandit-luks-reinstall.md)
│   └── bandit-lab/
│       ├── default.nix       # Hostname, SSH hardening, authorized keys
│       ├── hardware.nix      # Server filesystems/hardware
│       ├── auto-rebuild.nix  # lab-update tooling: poll GitHub, auto-apply timer, build, test, switch
│       ├── health-check.nix  # bandit-lab-health critical-unit check
│       ├── wan.nix           # Cloudflare Tunnel ingress
│       ├── webhost.nix       # Static web hosting / Caddy-adjacent services
│       ├── traefik.nix       # Reverse proxy + Docker service labels
│       ├── vaultwarden.nix   # Password manager container (+ Gruvbox web-vault theme)
│       ├── vaultwarden/      # gruvbox.scss.hbs theme source (TEMPLATES_FOLDER hook)
│       ├── llm.nix           # Ollama service
│       ├── mrija-archive.nix # Backup/archive service
│       ├── log-monitor.nix   # Log-based alerting
│       ├── monitoring.nix    # Grafana+Prometheus host files/secrets for the Portainer stack
│       ├── power.nix         # Server power settings
│       └── cockpit-theme.nix # Cockpit admin UI theming
├── nixos/                    # System-level NixOS modules
│   ├── default.nix           # Aggregator imported by bandit
│   ├── sops.nix              # sops-nix wiring and secret definitions
│   ├── core.nix              # Locale, timezone, nix daemon, GC, journald
│   ├── boot.nix              # Kernel packages, tmpfs, docs disabled
│   ├── network.nix           # NetworkManager, firewall, DNS-over-TLS
│   ├── graphics.nix          # AMD graphics, ROCm, Vulkan RADV
│   ├── firmware.nix          # fwupd, fprintd, AMD microcode, redistributable firmware
│   ├── power.nix             # zram, earlyoom, power-profiles-daemon, fstrim, btrfs scrub, battery threshold
│   ├── dev.nix               # direnv, nh, virt-manager, rootless Docker, Podman
│   ├── security-tools.nix    # Pentest/RE/privacy toolkit (bandit only) + Wireshark group
│   ├── audio.nix             # PipeWire low-latency config
│   ├── desktop.nix           # greetd/tuigreet, Hyprland, Bluetooth, polkit
│   ├── theme.nix             # Fonts and Stylix system targets
│   ├── users.nix             # User account, groups, sudo
│   ├── health-check.nix      # bandit-health system check
│   ├── cli-tools.nix         # CLI tools shared between hosts
│   ├── tor.nix               # Tor client configuration
│   ├── server.nix            # Headless server base module aggregator
│   ├── server/editor.nix     # Server-side editor/Zellij/Starship config
│   └── ci-overrides.nix      # CI-only sops validation override for bandit-ci
├── home/                     # Home Manager configuration
│   ├── default.nix           # Aggregator + user packages
│   ├── theme.nix             # HM Stylix targets + GTK CSS + Kvantum theme
│   ├── git.nix               # Git config, delta, GPG agent
│   ├── ssh.nix               # SSH client config and known-hosts
│   ├── qt.nix                # Qt/Kvantum theming
│   ├── xdg-cleanup.nix       # XDG cleanup rules
│   ├── node.nix              # Node.js tooling
│   ├── editor.nix            # Editor aggregator (nixvim, pdfreader)
│   ├── editor/nixvim.nix     # Full nixvim configuration
│   ├── editor/pdfreader.nix  # pdfreader.nvim setup
│   ├── editor/theme.nix      # nixvim theme tweaks
│   ├── terminal/             # Fish, Zsh, Kitty, Starship, tools, aliases, automation
│   └── desktop/              # Hyprland, Waybar, Mako, Rofi, Firefox, Thunderbird, etc.
├── secrets/                  # Encrypted secrets
│   ├── secrets.yaml          # General secrets
│   └── github.yaml           # GitHub SSH keys
├── ci/
│   └── vulnix-whitelist.toml # CVE allowlist for security scanning
├── script/                   # Local, gitignored helper scripts
├── themes/                   # Gruvbox base16 schemes (dark/light) + wallpaper
├── script/install-nixos.sh   # Generic live-ISO installer (gitignored, local-only)
├── script/install-bandit-lab.sh # bandit-lab-specific installer wrapper (gitignored)
├── script/install-bandit.sh  # bandit laptop reinstall: wipe disk, LUKS2, generate hardware.nix (gitignored)
└── .github/workflows/         # GitHub Actions CI
```

## 3. Flake Outputs

| Output | What It Builds |
|--------|----------------|
| `.#bandit` | Full laptop NixOS configuration: Hyprland, Home Manager, Stylix, nixvim, dev tooling. |
| `.#bandit-ci` | Same as `.#bandit` but with `nixos/ci-overrides.nix` so SOPS files do not need host keys during CI evaluation. |
| `.#bandit-lab` | Homelab server: headless shell, Docker services, Traefik, Cloudflare Tunnel, Tailscale, Samba, PostgreSQL. |
| `.#homeConfigurations.vino` | Standalone Home Manager configuration (useful for non-NixOS installs). |
| `.#checks.x86_64-linux.repository` | Formatter, linter, dead-code, statix. (Installer shellcheck/smoke tests were dropped when the installers moved to the gitignored `script/` directory.) |
| `.#checks.x86_64-linux.theme-contract` | Assertions that `lib/repository.nix` theme data matches the expected shape. |
| `.#checks.x86_64-linux.output-evaluation` | Records derivation paths of all public outputs. |
| `.#checks.x86_64-linux.home-manager-backup` | Tests the HM backup command used when files collide. |
| `.#formatter.x86_64-linux` | `alejandra` Nix formatter. |
| `.#packages.x86_64-linux.cachix` / `.#vulnix` | Utility packages exposed for CI/cache/security scanning. |

## 4. Build, Test, and Deployment Commands

All commands assume you are in the repo root with flakes enabled.

```bash
# Evaluate and lint everything (run before committing)
nix flake check --no-update-lock-file

# Build and activate the laptop configuration
sudo nixos-rebuild switch --flake .#bandit

# Test the laptop configuration without making it the default boot entry
sudo nixos-rebuild test --flake .#bandit

# Build and activate the homelab configuration
sudo nixos-rebuild switch --flake .#bandit-lab

# Dry-run evaluation without downloading/building closures
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --dry-run --no-update-lock-file
nix build .#nixosConfigurations.bandit-lab.config.system.build.toplevel --dry-run --no-update-lock-file

# Format all Nix files
nix run nixpkgs#alejandra -- .

# Run individual linters
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .

# Update dependencies
nix flake update
nix flake lock --update-input nixpkgs

# Edit secrets
sops secrets/secrets.yaml
sops secrets/github.yaml

# Local health checks (after rebuild)
bandit-health            # on bandit
bandit-lab-health        # on bandit-lab

# Homelab auto-updater
lab-update check         # poll GitHub for new commits
lab-update apply         # build, test, health-check, and switch to latest
# bandit-lab also auto-applies via the hourly lab-update-apply.timer (rolls back on failure)
```

## 5. Code Style and Conventions

- **Formatter:** `alejandra` with 2-space indentation. The flake exposes it as `.#formatter`.
- **Group options under a single attrset** per file. Avoid repeating top-level keys like `services`, `programs`, etc.
- **Imports rule:** `flake.nix` imports only host roots and aggregators (`./hosts/bandit`, `./nixos`, `./home`, `./hosts/bandit-lab`, `./nixos/server.nix`, `nixos/ci-overrides.nix`). Do **not** import individual leaf modules from `flake.nix`.
- **Shared constants** live in `lib/repository.nix`: `system`, `workstation.username`, `workstation.homeDirectory`, `workstation.repoPath`, `workstationTheme`, `serverPalette`, `allowUnfreePredicate`.
- **Theme files** are in `themes/`: `gruvbox-dark.yaml` (default), `gruvbox-light.yaml` (used by the `light` boot specialisation in `hosts/bandit/default.nix`), and the wallpaper `gruvbox_minimal_space.png`.
- **stateVersion** is pinned to `25.11` in `hosts/bandit/default.nix` and `home/default.nix`. Do not change it unless you understand the migration implications.
- **Unfree packages** are scoped by `lib/repository.nix::allowUnfreePredicate`. Only the named unfree packages and CUDA/libcu prefixes are allowed. Avoid global `allowUnfree = true`.
- **Shell aliases** shared between Fish and Zsh live in `home/terminal/aliases.nix`. Shell-specific aliases (`reload`, `paths`) and abbreviations live in their respective files.

## 6. Secrets Management

Secrets are managed with **sops-nix** and **age**.

- Encryption config: `.sops.yaml`
- Encrypted data: `secrets/secrets.yaml`, `secrets/github.yaml`
- Host age key at runtime: `/var/lib/sops-nix/key.txt`
  - Must be provisioned before secrets work.
  - `sops-nix` is configured with `generateKey = false` so a missing key fails loudly.

Active secrets referenced in `nixos/sops.nix` (plus the host-specific one noted) include:

| Secret | Purpose |
|--------|---------|
| `user-password` | Hashed user password (`neededForUsers = true`) |
| `github_ssh_key` | SSH key → `~/.ssh/github` |
| `github_ssh_key_banditstudent` | SSH key → `~/.ssh/github-banditstudent` |
| `cachix-secret` | Cachix auth token |
| `context7_api_key` | Context7 MCP API key |
| `vaultwarden-admin-token` | Vaultwarden admin token |
| `thehost-sshkey` | SSH key → `~/.ssh/thehost_mrija` |
| `firecrawl-api-key` | Firecrawl API key |
| `grafana-admin-password` | Declared in `hosts/bandit-lab/monitoring.nix` (mode 0400, owner `grafana` system user uid/gid 472); consumed by the Portainer monitoring stack via bind mount |
| `mrija-api-key` | mrija-archive admin API key; rendered by `hosts/bandit-lab/mrija-archive.nix` into `/run/secrets/rendered/mrija-archive.env` (container `env_file:` + sync service `EnvironmentFile`) |
| `mrija-password` | mrija-archive web login password; same rendered env file as above |

**Security rule:** Never commit plaintext secrets. Never modify `.sops.yaml` age/GPG keys without a backup and re-encryption plan.

## 7. Testing and CI

### GitHub Actions (`.github/workflows/test-nixos-config.yml`)

- **lint-commits:** Conventional commit messages on PRs.
- **label-pr:** Auto-label PRs by changed files.
- **build:** Runs `nix flake check`, then dry-runs `.#bandit-ci`.
- **build-vm:** Builds `.#bandit-ci.config.system.build.vm` and runs a 90-second boot smoke test.
- **security-scan:** Not present in the single workflow file currently; vulnix scanning is handled in GitLab CI.
- **populate-cache:** On push to main + manual. Builds the bandit-lab closure and pushes it to the `github-bandit-nix` Cachix cache (feeds the lab's hourly auto-apply). Requires the `CACHIX_AUTH_TOKEN` repository secret (same value as sops `cachix-secret` — re-sync after every token rotation).
- **update-flake:** Manually triggered workflow that runs `nix flake update` and opens a PR.

### GitLab CI (`.gitlab-ci.yml`)

Runs in stages:

1. **lint** — `nix flake check --no-update-lock-file`
2. **build** — Dry-runs all three NixOS outputs plus the standalone home output.
3. **test** — Builds `.#bandit-ci` and runs `vulnix` against the closure using `ci/vulnix-whitelist.toml`.
4. **cache** — Manual job to build and push the full closure to Cachix.

CI uses `nixos/nix` image with pinned digest. The build job uses `--dry-run` by default because full closures exceed shared-runner disk limits.

## 8. Architecture Rules

### Module Ownership

| Concern | File |
|---------|------|
| Flake entry / outputs | `flake.nix` |
| Shared constants | `lib/repository.nix` |
| Boot / kernel / tmpfs | `nixos/boot.nix` |
| Core system / locale / nix GC | `nixos/core.nix` |
| Fonts / Stylix (system) | `nixos/theme.nix` |
| Network / firewall / DNS | `nixos/network.nix` |
| Audio / PipeWire | `nixos/audio.nix` |
| Display / greetd / Hyprland | `nixos/desktop.nix` |
| Users / sudo | `nixos/users.nix` |
| Dev tooling / containers / VMs | `nixos/dev.nix` |
| Pentest / RE / privacy toolkit | `nixos/security-tools.nix` |
| Firmware / fwupd / fprintd | `nixos/firmware.nix` |
| Power / zram / trim / scrub | `nixos/power.nix` |
| Secrets wiring | `nixos/sops.nix` |
| Server base / SSH / Zellij | `nixos/server.nix`, `nixos/server/editor.nix` |
| Homelab services | `hosts/bandit-lab/*.nix` |
| Monitoring stack host files | `hosts/bandit-lab/monitoring.nix` |
| Hardware / filesystems | `hosts/<host>/hardware.nix` |
| Hyprland config | `home/desktop/hyprland.nix` |
| Waybar | `home/desktop/waybar.nix` |
| Rofi | `home/desktop/rofi-wayland.nix` |
| Mako | `home/desktop/mako.nix` |
| Firefox / Thunderbird | `home/desktop/firefox/`, `home/desktop/thunderbird.nix` |
| Obsidian vaults | `home/desktop/obsidian.nix` |
| nixvim | `home/editor/nixvim.nix` |
| Fish / Zsh / Kitty / Starship | `home/terminal/` |
| Git / GPG | `home/git.nix` |
| HM Stylix / GTK / Qt | `home/theme.nix`, `home/qt.nix` |

### Important Design Notes

- **Hyprland is installed system-wide** in `nixos/desktop.nix` via `programs.hyprland.enable`. In `home/desktop/hyprland.nix`, `package = null` and `portalPackage = null` to avoid reinstalling it as a user package.
- **Hyprland configuration is native Lua.** `home/desktop/hyprland.nix` is the source of truth and Home Manager generates `~/.config/hypr/hyprland.lua`. Lua mode skips legacy string entries in bindings, rules, and submaps, so keep those values structured with `_args` and `lib.generators.mkLuaInline` dispatchers. Do not edit the generated file.
- **Stylix's Hyprland target is disabled** in `home/theme.nix` so `home/desktop/hyprland.nix` owns the border colors (orange accent) without merge conflicts.
- **Rofi and Mako targets are also disabled** in `home/theme.nix` because they have hand-tuned themes in their own modules.
- **Laptop SSH server is disabled** (`services.openssh.enable = false` in `nixos/dev.nix`); the machine only initiates outbound connections.
- **DNS-over-TLS is opportunistic** (`DNSOverTLS = "opportunistic"`) so captive portals do not hard-fail.
- **Docker is rootless** on `bandit` (`virtualisation.docker.rootless.enable`). `docker-compose` is wired as a user-level Docker CLI plugin in `home/terminal/tools.nix`.
- **PipeWire config uses flat dot-notation keys** (`"default.clock.rate"`) because nested Nix attrsets produce JSON that PipeWire silently ignores.
- **Spacebar hardware workaround:** `hosts/bandit/hardware.nix` enables `services.keyd` (scoped to the internal keyboard `0001:0001`) to disable the misbehaving spacebar (`space = noop`) and map Caps Lock and Right Ctrl (`rightcontrol`) to space. Note: hwdb keymaps from earlier generations persist in the atkbd driver until reboot or `sudo setkeycodes 39 57; sudo setkeycodes 3a 58` — a "dead" Caps Lock was a stale hwdb keymap, not hardware. The physical root cause is still a TODO; inspect the key mechanism, contact, and keyboard ribbon before replacing the input cover, then remove the workaround.

## 9. Security Considerations

- **SSH:** `bandit` has no SSH server. `bandit-lab` has SSH with password auth disabled, root login disabled, and an authorized Ed25519 key only.
- **Sudo:** `wheelNeedsPassword = true`. On `bandit`, the user has passwordless `nixos-rebuild` only.
- **User groups:** `vino` is explicitly **not** in `input`, `storage`, or `podman` groups to reduce privilege surface. The `wireshark` group (added in `nixos/security-tools.nix`) is the deliberate exception — it grants packet capture without root via setcap `dumpcap`.
- **Trusted Nix users:** Only `root` and `vino` are `trusted-users` on the laptop; the security plan removed `vino` from trusted-users in some phases, but current `nixos/core.nix` keeps both. Check `docs/SECURITY-PLAN.md` for pending hardening decisions.
- **Secrets:** sops-nix with age, no plaintext in repo, scoped file permissions.
- **GPG agent:** Cache TTL defaults to 1 hour, max 4 hours.
- **Neovim:** Persistent undo/swap/backup are disabled for `*/secrets/*`, `*.age`, `*.env*` files.
- **Cachix token:** Provided via sops secret and injected only for the duration of a `cachix` call, never exported globally.
- **Homelab WAN access:** Only via Cloudflare Tunnel. Admin services (Cockpit, Portainer, Samba) are not port-forwarded; access them via SSH/Tailscale tunnels.

See `docs/SECURITY-PLAN.md` for the active security roadmap (LUKS, Secure Boot, further hardening).

## 10. Installation and Recovery

### bandit-lab Live ISO Install

```bash
git clone https://github.com/6FaNcY9/bandit-nix.git
cd bandit-nix
sudo ./script/install-bandit-lab.sh \
  --root-dev /dev/disk/by-id/<root-partition> \
  --boot-dev /dev/disk/by-id/<efi-partition> \
  --age-key /run/media/nixos/USB/key.txt
```

The installer:

- Formats the root partition as BTRFS.
- Creates subvolumes: `@`, `@home`, `@nix`, `@log`, `@snapshots`.
- Installs the age key to `/mnt/var/lib/sops-nix/key.txt`.
- Runs `nixos-install --flake .#bandit-lab --no-root-passwd`.

Resume modes (`--mode prepare|mount|install`) exist to recover from network failures without reformatting. For other hosts, use the generic `install-nixos.sh`.

### bandit Live ISO Reinstall (LUKS) — PLANNED

> **Current state:** `bandit` is **not** LUKS-encrypted and still uses the old `@var` BTRFS layout. The procedure below is the **planned** reinstall; see `docs/runbooks/bandit-luks-reinstall.md` for the full runbook. `hosts/bandit/hardware.nix` will be regenerated with LUKS UUIDs and the `@log` layout at that time.

```bash
git clone https://github.com/6FaNcY9/bandit-nix.git
cd bandit-nix
sudo ./script/install-bandit.sh \
  --disk /dev/nvme0n1 \
  --age-key /run/media/nixos/USB/key.txt
```

The installer would:

- **Erase the whole disk.** GPT layout: 1 GiB EFI partition + one LUKS2 (argon2id) container.
- Create BTRFS subvolumes inside LUKS: `@`, `@home`, `@nix`, `@log`, `@snapshots` (same layout as bandit-lab; the current `hardware.nix` still uses the old `@var` layout until the reinstall).
- Generate `hosts/bandit/hardware.nix` with the real disk UUIDs and `boot.initrd.luks` config.
- Defer to `install-nixos.sh` for format/mount/install, so the same `--mode prepare|mount|install` resume modes apply (LUKS is re-opened automatically).

Post-install: commit the generated `hosts/bandit/hardware.nix`, then optionally enroll the TPM2 (`systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p2`) once Secure Boot (lanzaboote) is in place.


### Post-Install (bandit-lab)

- `sudo tailscale up`
- `sudo smbpasswd -a vino`
- Provision Cloudflare Tunnel credentials in `secrets/secrets.yaml` as `cloudflare-tunnel-credentials`.
- Run `sudo nixos-rebuild switch --flake .#bandit-lab`.

## 11. Common Pitfalls

- **Outdated documentation:** `README.md` and `docs/codebase-review.md` still describe the previous XFCE+i3 stack and `tomorrow-night-eighties` theme in places. The current workstation stack is **Hyprland/Wayland** with the **Gruvbox** (morhetz) Stylix theme — dark by default, light via the `light` boot specialisation.
- **SOPS host keys:** If `nix flake check` or `nixos-rebuild` fails with sops validation errors, the host age key is likely missing or wrong. The CI output `.#bandit-ci` bypasses this.
- **NixVim follows:** Do **not** add `inputs.nixpkgs.follows = "nixpkgs"` to the `nixvim` input. NixVim upstream tests against its own pinned nixpkgs and warns when overridden.
- **Flake imports:** Do not import individual leaf `.nix` files directly from `flake.nix`; import host roots and aggregator modules only.
- **Wayland vs X11:** Many desktop modules assume Wayland (e.g. `wl-clipboard`, `grim`, `slurp`, `hyprlock`). Do not blindly copy them into an X11 host.
- **Hyprland activation:** Repository evaluation does not modify the running desktop. After validation, `sudo nixos-rebuild switch --flake .#bandit` is the privileged activation step; restart Hyprland or log out and back in before judging the native Lua configuration.

## 12. Verification

The repository currently passes:

```bash
nix flake check --no-update-lock-file
```

Run this before any commit. CI runs the same check plus dry-run builds and VM smoke tests.

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (60-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk go test             # Go test failures only (90%)
rtk jest                # Jest failures only (99.5%)
rtk vitest              # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk pytest              # Python test failures only (90%)
rtk rake test           # Ruby test failures only (90%)
rtk rspec               # RSpec test failures only (60%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
rtk uv run <cmd>        # Compact uv project command output
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%). Format flags (-c, -l, -L, -o, -Z) run raw.
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->
