# bandit-nix

A personal NixOS configuration flake for the `bandit` laptop and the `bandit-lab`
homelab server. It uses flakes, Home Manager, sops-nix, and Stylix for a fully
declarative system and user environment.

## 🖥️ System Information

- **Hosts**
  - `bandit` — Framework 13 laptop with an AMD Ryzen 7040 chipset.
  - `bandit-lab` — Headless homelab server.
- **User**: `vino`
- **NixOS channel**: `nixos-unstable` (targeting 25.11)
- **Architecture**: `x86_64-linux`

## ✨ Features

- **Flake-based** reproducible NixOS configuration.
- **Home Manager** integration for the `vino` user environment.
- **sops-nix** secret management with age encryption.
- **Framework 13 AMD** optimizations via `nixos-hardware`.
- **Hyprland/Wayland** desktop on `bandit` with Waybar, Mako, and Rofi.
- **Stylix** system-wide theming using the **Gruvbox** (morhetz) palette, dark by default with a light boot specialisation.
- **nixvim** declarative Neovim setup with LSP, DAP, and completions.
- **Fish + Zsh** shells sharing aliases from `home/terminal/aliases.nix`.
- **Rootless Docker + Podman** for container workflows.
- **CI checks** for formatting, linting, dead code, installer smoke tests, and theme-contract assertions.

## Flake Outputs

- `.#bandit` — Full laptop configuration: NixOS + Home Manager + Hyprland + Stylix + nixvim.
- `.#bandit-ci` — CI-safe laptop evaluation that skips SOPS host-key validation.
- `.#bandit-lab` — Headless homelab server with SSH, Cloudflare Tunnel, Traefik, Docker-backed services, Tailscale, Samba, PostgreSQL, and maintenance tooling.
- `.#homeConfigurations.vino` — Standalone Home Manager configuration.

## 📁 Project Structure

```text
.
├── flake.nix              # Flake entry point, outputs, and CI checks
├── flake.lock             # Pinned dependency graph
├── lib/repository.nix     # Shared constants: user, paths, theme, unfree policy
├── ci/                    # CI policy files, e.g. vulnix allowlist
├── .sops.yaml             # sops-nix encryption configuration
├── hosts/
│   ├── bandit/            # Laptop host configuration
│   │   ├── default.nix    # Hostname, stateVersion, bootloader
│   │   └── hardware.nix   # Filesystems, LUKS, kernel modules
│   └── bandit-lab/        # Homelab host and service modules
├── nixos/                 # System-level NixOS modules
│   ├── default.nix        # Aggregator for the bandit host
│   ├── core.nix           # Locale, nix daemon, GC, journald
│   ├── boot.nix           # Kernel packages, tmpfs
│   ├── network.nix        # NetworkManager, firewall, DNS-over-TLS
│   ├── desktop.nix        # greetd, Hyprland, Bluetooth, polkit
│   ├── theme.nix          # Fonts and Stylix system targets
│   ├── dev.nix            # Dev tooling, containers, VMs
│   ├── users.nix          # User account and groups
│   ├── sops.nix           # Secrets wiring
│   └── server.nix         # Headless server base aggregator
├── home/                  # Home Manager configuration
│   ├── default.nix        # Aggregator and user packages
│   ├── terminal/          # Fish, Zsh, Kitty, Starship, aliases
│   ├── desktop/           # Hyprland, Waybar, Mako, Rofi, Firefox, Thunderbird
│   ├── editor/            # nixvim, pdfreader
│   ├── theme.nix          # HM Stylix targets
│   ├── git.nix            # Git, delta, GPG agent
│   ├── ssh.nix            # SSH client config
│   └── qt.nix             # Qt/Kvantum theming
├── secrets/               # Encrypted secrets (sops-nix)
│   ├── secrets.yaml
│   └── github.yaml
├── script/                # Local, gitignored helper scripts
├── install-nixos.sh       # Generic live-ISO installer
└── install-bandit-lab.sh  # bandit-lab-specific installer wrapper
```

## 🚀 Installation

### bandit-lab Live ISO Install

From the NixOS live installer, connect to the network, clone this repo, and run:

```bash
git clone https://github.com/6FaNcY9/bandit-nix.git
cd bandit-nix
sudo ./install-bandit-lab.sh \
  --root-dev /dev/disk/by-id/<root-partition> \
  --boot-dev /dev/disk/by-id/<efi-partition> \
  --age-key /run/media/nixos/USB/key.txt
```

The installer formats the root partition as BTRFS, creates subvolumes for `/`,
`/home`, `/nix`, `/var/log`, and `/.snapshots`, installs the age key to
`/mnt/var/lib/sops-nix/key.txt`, and runs `nixos-install --flake .#bandit-lab`.

Resume modes exist to recover from network failures without reformatting:

```bash
# Only run install after a previous prepare/format
sudo ./install-bandit-lab.sh \
  --root-dev /dev/disk/by-id/<root-partition> \
  --boot-dev /dev/disk/by-id/<efi-partition> \
  --age-key /tmp/sops-age-key.txt \
  --mode install

# Mount existing subvolumes after a reboot
sudo ./install-bandit-lab.sh \
  --root-dev /dev/disk/by-id/<root-partition> \
  --boot-dev /dev/disk/by-id/<efi-partition> \
  --age-key /tmp/sops-age-key.txt \
  --mode mount
```

For other hosts, use the generic installer:

```bash
sudo ./install-nixos.sh \
  --host <flake-host> \
  --root-dev /dev/disk/by-id/<root-partition> \
  --boot-dev /dev/disk/by-id/<efi-partition> \
  --age-key /path/to/key.txt
```

### Post-Install (bandit-lab)

- Tailscale: `sudo tailscale up`
- Samba password: `sudo smbpasswd -a vino`
- Provision Cloudflare Tunnel credentials in `secrets/secrets.yaml` as
  `cloudflare-tunnel-credentials`.
- Rebuild: `sudo nixos-rebuild switch --flake .#bandit-lab`

### WAN Access

`bandit-lab` exposes public HTTP services through Cloudflare Tunnel for:

```text
bandit-lab.mrija.org
*.bandit-lab.mrija.org
```

SSH is also reachable from anywhere via Cloudflare Access at
`ssh-bandit-lab.mrija.org`; the local SSH client config is in `home/ssh.nix`.

Admin services (Cockpit, Portainer, Samba) are not port-forwarded. Access them
via SSH/Tailscale tunnels:

```bash
ssh -L 9090:127.0.0.1:9090 -L 9443:127.0.0.1:9443 vino@bandit-lab.mrija.org
```

Then open `https://127.0.0.1:9090` and `https://127.0.0.1:9443`.

### bandit-lab Updates

`bandit-lab` polls the public GitHub repository every ten minutes. Its guarded
apply timer also attempts signed updates hourly; disable
`lab-update-apply.timer` when manual-only control is needed. To apply a reviewed
revision immediately:

```bash
sudo lab-update apply
```

`lab-update apply` verifies the commit signature, builds and test-activates the
candidate, runs `bandit-lab-health` before and after the final switch, and
restores the previous configuration on failure. Ollama and its dependent LLM
log monitor are temporarily parked, with their modules and `/srv/ollama` data
preserved for later reactivation. See
[docs/runbooks/bandit-lab-updates.md](docs/runbooks/bandit-lab-updates.md) for
operational details.

## 🛠️ Build, Test, and Deploy

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

# Update all flake inputs
nix flake update
```

## 🔐 Secrets Management

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and age.

```bash
sops secrets/secrets.yaml
sops secrets/github.yaml
```

At runtime the host age key must exist at `/var/lib/sops-nix/key.txt`.
`sops-nix` is configured with `generateKey = false` so a missing key fails
loudly.

## 📝 Customization

- **Theme**: `lib/repository.nix` and `themes/gruvbox-dark.yaml` /
  `themes/gruvbox-light.yaml` define the Gruvbox (morhetz) Stylix theme;
  the light variant is the `light` boot specialisation in
  `hosts/bandit/default.nix`.
- **Window manager**: `home/desktop/hyprland.nix` is the source of truth. Home
  Manager renders it as native Lua at `~/.config/hypr/hyprland.lua`; do not edit
  that generated file. Lua-mode bindings, rules, and submaps must use structured
  entries because legacy Hyprland configuration strings are not rendered.
- **Status bar / notifications**: `home/desktop/waybar.nix` and
  `home/desktop/mako.nix`.
- **Shells**: `home/terminal/fish.nix`, `home/terminal/zsh.nix`, and shared
  aliases in `home/terminal/aliases.nix`.
- **Editor**: `home/editor/nixvim.nix`.
- **Shared constants**: `lib/repository.nix` holds `system`, username,
  home/repository paths, the unfree package policy, and theme helpers.

After changing the Hyprland module, validate the flake before activating it:

```bash
nix flake check --no-update-lock-file
sudo nixos-rebuild switch --flake .#bandit
```

The rebuild is the privileged boundary that installs the generated Lua file.
Restart Hyprland or log out and back in afterward so the running compositor uses
the new configuration.

## 📄 License

This configuration is provided as-is for personal and educational use.
