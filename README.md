# bandit-nix

A personal NixOS configuration for the "bandit" host, built from scratch with minimal LLM assistance. This configuration manages a complete NixOS system with home-manager integration, secrets management, and a customized desktop environment.

## 🖥️ System Information

- **Host**: bandit (Framework 13 with AMD 7040 chipset)
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
│   ├── shell.nix          # Shell environment and aliases
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

After first boot:

- Cockpit server UI: `https://bandit-lab:9090`
- Portainer container UI: `https://bandit-lab:9443`
- Tailscale: `sudo tailscale up`
- Samba password for file storage: `sudo smbpasswd -a vino`
- Shared storage path: `/srv/storage`
- Container data path: `/srv/containers`

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
- **Shell**: Customize your shell in `home/shell.nix`
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
