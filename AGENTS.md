# bandit-nix — Agent Guide

Personal NixOS configuration flake, two hosts:

- **`bandit`** — Framework 13 laptop, AMD Ryzen 7040, daily driver.
- **`bandit-lab`** — Headless homelab server.

Nix Flake on `nixos-unstable`: NixOS system configurations, standalone Home Manager configuration for user `vino`, CI checks.

## 1. Technology Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| OS | NixOS 25.11 (`nixos-unstable`) | Declarative Linux |
| User env | Home Manager (master) | Dotfiles, packages, services |
| Editor | nixvim | Declarative Neovim (LSP, DAP, cmp) |
| Theming | Stylix + custom base16 | System + HM color/font/cursor |
| Secrets | sops-nix + age | Runtime secrets via `/var/lib/sops-nix/key.txt` |
| Hardware | nixos-hardware | Framework 13 AMD 7040 tweaks |
| Window manager | Hyprland (Wayland) | Compositor on `bandit` |
| Bars/notifications | Waybar / Mako | Status bar, notifications |
| Launcher | Rofi (Wayland build via `pkgs.rofi`) | App launcher |
| Terminals | Kitty | Primary emulator |
| Shells | Fish + Zsh | Shared aliases `home/terminal/aliases.nix` |
| Version control | Git + GPG signing | Commit signing, GitHub CLI |
| Containers | Rootless Docker + Podman | Dev on `bandit`; Docker services on `bandit-lab` |
| Server services | Traefik, Cloudflared, Tailscale, Samba, PostgreSQL, Vaultwarden, Portainer, Cockpit, SearXNG, WatchYourLAN | `bandit-lab` homelab stack |

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
│       ├── wan.nix           # Cloudflare Tunnel (remotely managed — see docs/runbooks/cloudflare-access.md)
│       ├── webhost.nix       # Static web hosting / Caddy-adjacent services
│       ├── traefik.nix       # Reverse proxy + Docker service labels
│       ├── vaultwarden.nix   # Password manager container (+ Gruvbox web-vault theme)
│       ├── searxng.nix       # Private metasearch container (stateless)
│       ├── watchyourlan.nix  # LAN device-discovery container (host network, loopback GUI)
│       ├── wazuh.nix         # Wazuh SIEM stack (manager/indexer/dashboard/agent oci-containers)
│       ├── wazuh/            # Wazuh configs + public TLS certs (keys in sops)
│       ├── vaultwarden/      # gruvbox.scss.hbs theme source (TEMPLATES_FOLDER hook)
│       ├── mrija-archive.nix # Backup/archive service
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
│   ├── gaming.nix            # Steam, Proton-GE, gamescope, gamemode, MangoHud (bandit only)
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
| `.#bandit` | Laptop: Hyprland, Home Manager, Stylix, nixvim, dev tooling. |
| `.#bandit-ci` | `.#bandit` + `nixos/ci-overrides.nix`; SOPS needs no host keys in CI. |
| `.#bandit-lab` | Homelab: headless shell, Docker services, Traefik, Cloudflare Tunnel, Tailscale, Samba, PostgreSQL. |
| `.#homeConfigurations.vino` | Standalone Home Manager (non-NixOS installs). |
| `.#checks.x86_64-linux.repository` | Formatter, linter, dead-code, statix (installer shellcheck/smoke tests dropped when installers moved to gitignored `script/`). |
| `.#checks.x86_64-linux.theme-contract` | `lib/repository.nix` theme shape assertions. |
| `.#checks.x86_64-linux.output-evaluation` | Derivation paths of all public outputs. |
| `.#checks.x86_64-linux.home-manager-backup` | HM backup command for file collisions. |
| `.#formatter.x86_64-linux` | `alejandra`. |
| `.#packages.x86_64-linux.cachix` / `.#vulnix` | CI/cache/security-scan utilities. |

## 4. Build, Test, and Deployment Commands

Run from repo root, flakes enabled.

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

- **Formatter:** `alejandra`, 2-space indent; exposed as `.#formatter`.
- **Single attrset per file**; no repeated top-level keys (`services`, `programs`, etc.).
- **Imports:** `flake.nix` imports only host roots/aggregators (`./hosts/bandit`, `./nixos`, `./home`, `./hosts/bandit-lab`, `./nixos/server.nix`, `nixos/ci-overrides.nix`) — never leaf modules.
- **Shared constants** `lib/repository.nix`: `system`, `workstation.username`, `workstation.homeDirectory`, `workstation.repoPath`, `workstationTheme`, `serverPalette`, `allowUnfreePredicate`.
- **Themes** `themes/`: `gruvbox-dark.yaml` (default), `gruvbox-light.yaml` (`light` boot specialisation, `hosts/bandit/default.nix`), wallpaper `gruvbox_minimal_space.png`.
- **stateVersion** pinned `25.11` (`hosts/bandit/default.nix`, `home/default.nix`); change only with migration plan.
- **Unfree** scoped by `lib/repository.nix::allowUnfreePredicate` (named packages + CUDA/libcu prefixes only); never global `allowUnfree = true`.
- **Aliases** shared Fish/Zsh: `home/terminal/aliases.nix`; shell-specific (`reload`, `paths`) + abbreviations in per-shell files.

## 6. Secrets Management

**sops-nix** + **age**. Config `.sops.yaml`; data `secrets/secrets.yaml`, `secrets/github.yaml`; host age key `/var/lib/sops-nix/key.txt` (provision first; `generateKey = false` → missing key fails loudly).

Active secrets in `nixos/sops.nix` (+ host-specific noted):

| Secret | Purpose |
|--------|---------|
| `user-password` | Hashed user password (`neededForUsers = true`) |
| `github_ssh_key` | SSH key → `~/.ssh/github` |
| `github_ssh_key_banditstudent` | SSH key → `~/.ssh/github-banditstudent` |
| `cachix-secret` | Cachix auth token |
| `cloudflare-api-key` | Cloudflare token → `CLOUDFLARE_API_TOKEN` env var (zsh/fish) for REST curl calls |
| `context7_api_key` | Context7 MCP API key |
| `vaultwarden-admin-token` | Vaultwarden admin token |
| `thehost-sshkey` | SSH key → `~/.ssh/thehost_mrija` |
| `firecrawl-api-key` | Firecrawl API key |
| `shodan-api-key` | Shodan Membership key; fish/zsh `shodan` wrapper runs `shodan init` from it on first use |
| `grafana-admin-password` | `hosts/bandit-lab/monitoring.nix` (mode 0400, `grafana` uid/gid 472); Portainer stack bind mount |
| `mrija-api-key` | mrija-archive admin key; rendered by `hosts/bandit-lab/mrija-archive.nix` → `/run/secrets/rendered/mrija-archive.env` (container `env_file:` + sync `EnvironmentFile`) |
| `mrija-password` | mrija-archive web login password; same rendered env file |

**Security rule:** never commit plaintext secrets; never modify `.sops.yaml` age/GPG keys without backup + re-encryption plan.

## 7. Testing and CI

### GitHub Actions (`.github/workflows/test-nixos-config.yml`)

- **lint-commits:** conventional commits on PRs.
- **label-pr:** auto-label PRs by changed files.
- **build:** `nix flake check`, dry-run `.#bandit-ci`.
- **build-vm:** builds `.#bandit-ci.config.system.build.vm`, 90 s boot smoke test.
- **security-scan:** not in this workflow; vulnix scan in GitLab CI.
- **populate-cache:** push to main + manual; bandit-lab closure → `github-bandit-nix` Cachix cache (feeds lab's hourly auto-apply). Needs `CACHIX_AUTH_TOKEN` repo secret (= sops `cachix-secret`; re-sync after every rotation).
- **update-flake:** manual; `nix flake update` + PR.

### GitLab CI (`.gitlab-ci.yml`)

1. **lint** — `nix flake check --no-update-lock-file`
2. **build** — dry-runs 3 NixOS outputs + standalone home output.
3. **test** — builds `.#bandit-ci`, runs `vulnix` with `ci/vulnix-whitelist.toml`.
4. **cache** — manual; build + push full closure to Cachix.

`nixos/nix` image, pinned digest. Build job `--dry-run` by default (closures exceed shared-runner disk).

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
| Gaming / Steam / Proton | `nixos/gaming.nix` |
| Pentest / RE / privacy toolkit | `nixos/security-tools.nix` |
| Firmware / fwupd / fprintd | `nixos/firmware.nix` |
| Power / zram / trim / scrub | `nixos/power.nix` |
| Secrets wiring | `nixos/sops.nix` |
| Server base / SSH / Zellij | `nixos/server.nix`, `nixos/server/editor.nix` |
| Homelab services | `hosts/bandit-lab/*.nix` |
| Monitoring stack host files | `hosts/bandit-lab/monitoring.nix` |
| Wazuh SIEM stack | `hosts/bandit-lab/wazuh.nix` (+ `wazuh/` configs/certs; secrets in sops) |
| Hardware / filesystems | `hosts/<host>/hardware.nix` |
| Hyprland config | `home/desktop/hyprland.nix` |
| Waybar | `home/desktop/waybar.nix` |
| Rofi | `home/desktop/rofi-wayland.nix` |
| Keybinding browser (SUPER+F2) | `home/desktop/keybinds-menu.nix` |
| Mako | `home/desktop/mako.nix` |
| Firefox / Thunderbird | `home/desktop/firefox/`, `home/desktop/thunderbird.nix` |
| Obsidian vaults | `home/desktop/obsidian.nix` |
| nixvim | `home/editor/nixvim.nix` |
| Fish / Zsh / Kitty / Starship | `home/terminal/` |
| Git / GPG | `home/git.nix` |
| HM Stylix / GTK / Qt | `home/theme.nix`, `home/qt.nix` |

### Important Design Notes

- **Hyprland system-wide** via `programs.hyprland.enable` (`nixos/desktop.nix`); `home/desktop/hyprland.nix` sets `package = null` + `portalPackage = null` (no user-level reinstall).
- **Hyprland config = native Lua:** source of truth `home/desktop/hyprland.nix`; HM generates `~/.config/hypr/hyprland.lua` (never edit). Lua mode skips legacy string entries in bindings/rules/submaps — use structured `_args` + `lib.generators.mkLuaInline` dispatchers.
- **Stylix targets disabled** in `home/theme.nix`: Hyprland (borders owned by `home/desktop/hyprland.nix`, orange accent), Rofi + Mako (hand-tuned in own modules).
- **Laptop SSH server disabled** (`services.openssh.enable = false`, `nixos/dev.nix`); outbound only.
- **DNS-over-TLS opportunistic** (`DNSOverTLS = "opportunistic"`): captive portals don't hard-fail.
- **Docker rootless** on `bandit` (`virtualisation.docker.rootless.enable`); `docker-compose` = user-level CLI plugin (`home/terminal/tools.nix`).
- **PipeWire flat dot-notation keys** (`"default.clock.rate"`); nested attrsets → JSON PipeWire silently ignores.
- **Spacebar workaround:** `hosts/bandit/hardware.nix` enables `services.keyd` (internal keyboard `0001:0001` only): spacebar `space = noop`, Caps Lock + Right Ctrl (`rightcontrol`) → space. Stale hwdb keymaps persist in atkbd until reboot or `sudo setkeycodes 39 57; sudo setkeycodes 3a 58` — "dead" Caps Lock = stale keymap, not hardware. Root cause TODO: inspect key mechanism, contact, ribbon before replacing input cover; then remove workaround.

## 9. Security Considerations

- **SSH:** `bandit` none. `bandit-lab` (`hosts/bandit-lab/default.nix`): no password auth, no root login, `AllowUsers` `vino`, Ed25519 keys only; fail2ban 1 h escalating bans (≤1 week, maxretry 3), Tailscale `100.64.0.0/10` exempt.
- **Samba** (`hosts/bandit-lab/webhost.nix`): SMB2 min, `hosts allow` loopback + private LAN + tailnet, per-interface `enp44s0` firewall openings.
- **Health gate:** `bandit-lab-health` (`hosts/bandit-lab/health-check.nix`) critical units `sshd`, `fail2ban`, `samba-smbd`; config killing remote access rolls back instead of deploying.
- **Sudo:** `wheelNeedsPassword = true`; `bandit` passwordless `nixos-rebuild` only.
- **Groups:** `vino` **not** in `input`/`storage`/`podman` (privilege surface); exception `wireshark` (`nixos/security-tools.nix`) — capture without root via setcap `dumpcap`.
- **`trusted-users`:** laptop `root` + `vino` (`nixos/core.nix`); `bandit-lab` forced `trusted-users = ["root"]` (`hosts/bandit-lab/default.nix`; `lab-update` runs as root).
- **Secrets:** sops-nix + age, no plaintext in repo, scoped permissions.
- **GPG agent:** cache TTL 1 h default, 4 h max.
- **Neovim:** no persistent undo/swap/backup for `*/secrets/*`, `*.age`, `*.env*`.
- **Cachix token:** sops-provided, injected only during a `cachix` call, never exported globally.
- **WAN:** Cloudflare Tunnel only. Admin services (Cockpit, Portainer, Samba) not port-forwarded — access via SSH/Tailscale tunnels. Tunnel **remotely managed**: dashboard Public Hostnames authoritative, applied in seconds; `hosts/bandit-lab/wan.nix` = documentation mirror, keep synced (`docs/runbooks/cloudflare-access.md`).

Security roadmap (LUKS, Secure Boot, hardening): `docs/SECURITY-PLAN.md`.

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

Installer: formats root BTRFS; subvolumes `@`, `@home`, `@nix`, `@log`, `@snapshots`; age key → `/mnt/var/lib/sops-nix/key.txt`; runs `nixos-install --flake .#bandit-lab --no-root-passwd`. Resume modes `--mode prepare|mount|install` recover from network failures without reformatting. Other hosts: generic `install-nixos.sh`.

### bandit Live ISO Reinstall (LUKS) — PLANNED

> **Current state:** `bandit` **not** LUKS-encrypted, still old `@var` BTRFS layout. Below = **planned** reinstall (runbook `docs/runbooks/bandit-luks-reinstall.md`); `hosts/bandit/hardware.nix` regenerated with LUKS UUIDs + `@log` layout then.

```bash
git clone https://github.com/6FaNcY9/bandit-nix.git
cd bandit-nix
sudo ./script/install-bandit.sh \
  --disk /dev/nvme0n1 \
  --age-key /run/media/nixos/USB/key.txt
```

Installer would: erase whole disk (GPT: 1 GiB EFI + LUKS2 argon2id container); BTRFS subvolumes inside LUKS `@`, `@home`, `@nix`, `@log`, `@snapshots` (bandit-lab layout; current `hardware.nix` keeps `@var` layout until reinstall); generate `hosts/bandit/hardware.nix` with real disk UUIDs + `boot.initrd.luks`; defer to `install-nixos.sh` for format/mount/install (same `--mode prepare|mount|install` resume modes; LUKS auto re-opened).

Post-install: commit generated `hosts/bandit/hardware.nix`; optionally enroll TPM2 (`systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p2`) once Secure Boot (lanzaboote) in place.


### Post-Install (bandit-lab)

- `sudo tailscale up`
- `sudo smbpasswd -a vino`
- Provision Cloudflare Tunnel credentials in `secrets/secrets.yaml` as `cloudflare-tunnel-credentials`.
- Run `sudo nixos-rebuild switch --flake .#bandit-lab`.

## 11. Common Pitfalls

- **Outdated docs:** `README.md`, `docs/codebase-review.md` still describe old XFCE+i3 stack / `tomorrow-night-eighties` theme. Current: **Hyprland/Wayland** + **Gruvbox** (morhetz) Stylix — dark default, light via `light` boot specialisation.
- **SOPS host keys:** sops validation errors in `nix flake check`/`nixos-rebuild` → host age key missing/wrong; `.#bandit-ci` bypasses.
- **NixVim follows:** never add `inputs.nixpkgs.follows = "nixpkgs"` to `nixvim` input — upstream tests against own pinned nixpkgs, warns when overridden.
- **Flake imports:** no leaf `.nix` files in `flake.nix`; host roots + aggregators only.
- **Wayland vs X11:** desktop modules assume Wayland (`wl-clipboard`, `grim`, `slurp`, `hyprlock`); don't copy to X11 hosts.
- **Hyprland activation:** evaluation ≠ running desktop. Activate `sudo nixos-rebuild switch --flake .#bandit`, then restart Hyprland / re-login before judging Lua config.

## 12. Verification

Passes:

```bash
nix flake check --no-update-lock-file
```

Run before any commit. CI runs same check + dry-run builds + VM smoke tests.

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`** — dedicated filter if available, else passthrough unchanged; always safe, even in `&&` chains:
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

Git passthrough works for ALL subcommands, even unlisted ones.

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
