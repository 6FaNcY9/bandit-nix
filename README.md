# bandit-nix

A personal NixOS configuration for the `bandit` laptop and `bandit-lab` homelab host. This flake manages NixOS systems with home-manager integration, secrets management, CI evaluation, and a customized desktop environment.

## 🖥️ System Information

- **Hosts**: bandit (Framework 13 with AMD 7040 chipset), bandit-lab (homelab server)
- **User**: vino
- **NixOS Version**: 25.11
- **Architecture**: x86_64-linux

## ✨ Features

- **Flake-based Configuration**: Modern, reproducible NixOS setup using flakes
- **Home Manager Integration**: User environment management with declarative home configurations
- **Secrets Management**: Secure secrets handling with sops-nix and age encryption
- **Hardware Optimization**: Framework 13 AMD-specific optimizations via nixos-hardware
- **Firmware + Security Maintenance**: fwupd, fprintd, fstrim, and btrfs auto-scrub enabled
- **Neovim Configuration**: Declarative Neovim setup with nixvim
- **Theme Management**: System-wide theming with Stylix
- **Desktop Environment**: i3 window manager with XFCE panel integration
- **Developer Tooling**: OpenSSH, podman, libvirt, direnv, and local CI linters available system-wide
- **Modular Structure**: Clean separation of system and user configurations

## Flake Outputs

- `.#bandit` - laptop workstation configuration with Home Manager, Stylix, nixvim, i3, and desktop tooling.
- `.#bandit-ci` - CI-safe evaluation output for the laptop configuration; imports `nixos/ci-overrides.nix` so encrypted SOPS files do not need host keys in CI.
- `.#bandit-lab` - homelab server configuration with SSH, Cloudflare Tunnel, Traefik, Docker-backed services, Tailscale, Samba, PostgreSQL, and server maintenance defaults.

## 📁 Project Structure

```
.
├── flake.nix              # Main flake configuration and system entry point
├── flake.lock             # Locked dependency versions
├── .sops.yaml             # Secrets encryption configuration
├── hosts/
│   └── bandit/            # Host-specific configurations
│       ├── default.nix    # Host configuration
│       └── hardware.nix   # Hardware-specific settings
├── nixos/                 # System-level NixOS configurations
│   ├── default.nix        # Main system module imports
│   ├── core.nix           # Core system packages and settings
│   ├── boot.nix           # Bootloader configuration
│   ├── network.nix        # Network settings
│   ├── graphics.nix       # AMD graphics/Vulkan/OpenCL stack
│   ├── firmware.nix       # Framework firmware + fingerprint support
│   ├── power.nix          # Power profile, suspend, trim, and scrub
│   ├── dev.nix            # Dev tooling, SSH, containers, virtualization
│   ├── audio.nix          # Audio configuration
│   ├── desktop.nix        # Desktop environment setup
│   └── users.nix          # User account definitions
├── home/                  # Home Manager user configurations
│   ├── default.nix        # Main home configuration
│   ├── terminal/          # Shells, prompt, terminal tools
│   ├── editor.nix         # Text editor configuration
│   ├── git.nix            # Git configuration
│   ├── theme.nix          # User theme settings
│   └── desktop/           # Desktop-specific home configs
│       ├── i3.nix         # i3 window manager config
│       └── xfce-panel.nix # XFCE panel configuration
├── modules/               # Custom NixOS modules (if any)
└── secrets/               # Encrypted secrets (sops)
    └── secrets.yaml       # Encrypted secrets file
```

## 🚀 Installation

### bandit-lab Live ISO Install

From the NixOS live installer, connect to the network, clone this repo, and run:

```bash
git clone https://github.com/6FaNcY9/bandit-nix.git
cd bandit-nix
sudo ./install-bandit-lab.sh --age-key /run/media/nixos/USB/key.txt
```

Defaults match the current planned lab disk layout:

- Root/NixOS target: `/dev/nvme0n1p5`
- Existing EFI partition: `/dev/nvme0n1p1`
- Host flake output: `.#bandit-lab`

Override devices when needed:

```bash
sudo ./install-bandit-lab.sh \
  --root-dev /dev/disk/by-id/<root-partition> \
  --boot-dev /dev/disk/by-id/<efi-partition> \
  --age-key /run/media/nixos/USB/key.txt
```

The script formats only the root partition and creates BTRFS subvolumes for
`/`, `/home`, `/nix`, `/var/log`, and `/.snapshots`. It also installs the
sops-nix age key to `/var/lib/sops-nix/key.txt` before running
`nixos-install --flake .#bandit-lab`.

If networking fails during `nixos-install`, do not rerun the default command
unless you want to format again. Fix networking and resume only the install
phase:

```bash
sudo ./install-bandit-lab.sh \
  --age-key /tmp/sops-age-key.txt \
  --mode install
```

If you rebooted after formatting, mount the existing BTRFS subvolumes first,
then install:

```bash
sudo ./install-bandit-lab.sh \
  --age-key /tmp/sops-age-key.txt \
  --mode mount

sudo ./install-bandit-lab.sh \
  --age-key /tmp/sops-age-key.txt \
  --mode install
```

For other hosts or machines, use the generic installer directly:

```bash
sudo ./install-nixos.sh \
  --host <flake-host> \
  --root-dev /dev/disk/by-id/<root-partition> \
  --boot-dev /dev/disk/by-id/<efi-partition> \
  --age-key /path/to/key.txt
```

After first boot:

- Cockpit server UI: `https://bandit-lab:9090`
- Portainer container UI: `https://bandit-lab:9443`
- Tailscale: `sudo tailscale up`
- Samba password for file storage: `sudo smbpasswd -a vino`
- Shared storage path: `/srv/storage`
- Container data path: `/srv/containers`

### WAN Access

`bandit-lab` exposes public HTTP services through Cloudflare Tunnel for:

```text
bandit-lab.mrija.org
```

Cloudflare Tunnel expects a sops secret named
`cloudflare-tunnel-credentials` containing the tunnel credentials JSON.
Provision the host age key at `/var/lib/sops-nix/key.txt`, add the encrypted
secret to `secrets/secrets.yaml`, then rebuild:

```bash
sudo nixos-rebuild switch --flake .#bandit-lab
```

No router port forwarding is required for the tunnel path. Do not expose
Cockpit, Samba, Portainer, or direct Traefik ports to the WAN.

Admin access should use SSH/Tailscale tunnels:

```bash
ssh -L 9090:127.0.0.1:9090 -L 9443:127.0.0.1:9443 vino@bandit-lab.mrija.org
```

Then open:

```text
https://127.0.0.1:9090
https://127.0.0.1:9443
```

### Prerequisites

1. A working NixOS installation
2. Nix flakes enabled in your configuration
3. Git installed

### Enable Flakes

If flakes aren't already enabled, add to your `/etc/nixos/configuration.nix`:

```nix
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
```

Then rebuild: `sudo nixos-rebuild switch`

### Clone and Deploy

1. Clone this repository:
```bash
git clone https://github.com/6FaNcY9/bandit-nix.git
cd bandit-nix
```

2. Review and customize the configuration:
   - Edit `hosts/bandit/default.nix` to set your hostname
   - Update `home/default.nix` with your username and home directory
   - Modify `nixos/users.nix` to create your user account

3. Build and switch to the new configuration:
```bash
sudo nixos-rebuild switch --flake .#bandit
```

## 🔐 Secrets Management

This configuration uses [sops-nix](https://github.com/Mic92/sops-nix) for managing secrets.

### Setting Up Secrets

1. Generate an age key:
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

2. Update `.sops.yaml` with your public key
3. Edit secrets:
```bash
sops secrets/secrets.yaml
```

## 🛠️ Configuration

### Flake Inputs

- **nixpkgs**: NixOS unstable channel
- **home-manager**: User environment management
- **sops-nix**: Secrets management with age encryption
- **nixvim**: Neovim configuration in Nix
- **stylix**: System-wide theme management
- **nixos-hardware**: Hardware-specific optimizations

### Adding New Packages

- **System packages**: Add to `nixos/core.nix`
- **User packages**: Add to relevant files in `home/`

### Modifying the Configuration

1. Make your changes to the appropriate `.nix` files
2. Test the configuration:
```bash
sudo nixos-rebuild test --flake .#bandit
```
3. If everything works, make it permanent:
```bash
sudo nixos-rebuild switch --flake .#bandit
```

## 🔄 Updating

Update all flake inputs:
```bash
nix flake update
```

Update specific input:
```bash
nix flake lock --update-input nixpkgs
```

After updating, rebuild:
```bash
sudo nixos-rebuild switch --flake .#bandit
```

## 📝 Customization Tips

- **Theme**: Stylix configuration can be adjusted in the relevant home/nixos files
- **Window Manager**: i3 configuration is in `home/desktop/i3.nix`
- **Shell**: Customize shells and prompt under `home/terminal/`
- **Git**: Git settings are in `home/git.nix`
- **Editor**: Neovim/editor configs are in `home/editor.nix`

## 🤝 Contributing

This is a personal configuration, but feel free to:
- Fork it for your own use
- Open issues for questions or suggestions
- Submit PRs for improvements

## 📄 License

This configuration is provided as-is for personal and educational use.

## 🙏 Acknowledgments

- [NixOS](https://nixos.org/) - The amazing Linux distribution
- [home-manager](https://github.com/nix-community/home-manager) - Declarative home configuration
- [sops-nix](https://github.com/Mic92/sops-nix) - Secrets management
- [nixvim](https://github.com/nix-community/nixvim) - Neovim in Nix
- [stylix](https://github.com/danth/stylix) - System-wide theming
- [nixos-hardware](https://github.com/NixOS/nixos-hardware) - Hardware optimizations

## 📚 Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Package Search](https://search.nixos.org/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [NixOS Wiki](https://nixos.wiki/)

---

*Built with ❤️ and Nix*
