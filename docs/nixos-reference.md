# NixOS / Home Manager Reference

Practical reference for the `bandit-nix` flake config. Covers module system,
common patterns, HM options, debugging, and tooling.

---

## Module System

### Priority functions (high number wins)

| Function | Priority | Use case |
|----------|----------|----------|
| `lib.mkDefault x` | 1000 | Set a default, allow override |
| `lib.mkOptionDefault x` | 1500 | Internal default (rarely used directly) |
| _(plain value)_ | 100 | Normal assignment |
| `lib.mkForce x` | 50 (inverted — wins) | Override everything else |
| `lib.mkOverride n x` | n | Custom priority |

**Rule of thumb:** conflicting definitions at the same priority are an error. Use
`mkForce` to win over a library default; use `mkDefault` to lose gracefully to
any explicit value.

### Conditional options

```nix
# Enable only when condition is true
option = lib.mkIf condition value;

# Merge multiple attrsets conditionally
imports = lib.optionals condition [ ./module.nix ];
```

### Merging

```nix
# Merge two attrsets (right wins on conflict)
lib.mkMerge [ { a = 1; } { b = 2; } ]

# Concat lists from multiple modules — use mkAfter/mkBefore for ordering
environment.systemPackages = lib.mkAfter [ pkgs.ripgrep ];
```

### Module arguments

```nix
# Access flake inputs inside any NixOS module (requires specialArgs in flake.nix)
{ inputs, pkgs, lib, config, ... }: { ... }

# Home Manager modules get these via extraSpecialArgs
{ inputs, pkgs, lib, config, ... }: { ... }
```

---

## Flake Structure (`flake.nix` patterns)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";   # share nixpkgs, avoid duplication
    };
    stylix.url = "github:nix-community/stylix";
  };

  outputs = { self, nixpkgs, home-manager, stylix, ... }@inputs: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };   # makes `inputs` available in modules
      modules = [
        home-manager.nixosModules.home-manager
        stylix.nixosModules.stylix
        ./hosts/hostname
        ./nixos
        ./home  # HM as NixOS module; needs home-manager.users.vino = import ./home
      ];
    };
  };
}
```

### specialArgs vs extraSpecialArgs

| | Scope | How to pass |
|--|-------|-------------|
| `specialArgs` | NixOS modules | `nixpkgs.lib.nixosSystem { specialArgs = {...}; }` |
| `extraSpecialArgs` | HM modules only | `home-manager.extraSpecialArgs = {...};` |

When HM is a NixOS module, `specialArgs` values are also available in HM
modules by default. You can still use `extraSpecialArgs` for HM-only values.

---

## Home Manager as NixOS Module

```nix
# In any NixOS module:
home-manager = {
  useGlobalPkgs = true;       # HM uses system nixpkgs (no double eval)
  useUserPackages = true;     # packages go into /etc/profiles/per-user
  backupFileExtension = "bak"; # prevents activation failure on conflicts
  users.vino = import ./home;
  extraSpecialArgs = { inherit inputs; };
};
```

**`useGlobalPkgs = true`** is almost always correct — avoids a second nixpkgs
evaluation and makes overlays apply uniformly.

---

## Finding Options

### Search online
- NixOS options: https://search.nixos.org/options (filter by channel)
- HM options: https://home-manager-options.extendnixos.org
- Packages: https://search.nixos.org/packages

### Search locally
```bash
# Find all options matching a pattern
nixos-option services.xserver
nixos-option home-manager.users

# List all HM options (very long)
man home-configuration.nix

# Search HM options source
grep -r "mkOption" $(nix eval --raw nixpkgs#home-manager)/modules/ | grep "xfconf"
```

### Read Stylix source options
```bash
# Find where Stylix is in the store
nix eval --raw 'inputs.stylix' 2>/dev/null || ls /nix/store | grep stylix | head -5

# Read a specific target module
cat /nix/store/<stylix-hash>/modules/xfce/hm.nix
cat /nix/store/<stylix-hash>/modules/i3/hm.nix
cat /nix/store/<stylix-hash>/hm/integration.nix   # autoImport behavior
```

---

## Stylix Integration

### Key behavior (autoImport)

With `home-manager.nixosModules.home-manager`, Stylix needs `autoImport = true`
(the default) to propagate config to HM:

```nix
# nixos/core.nix — DO NOT add homeManagerIntegration.autoImport = false
# That disables copyModules, causing all HM targets to silently do nothing
# because config.stylix.enable is false in HM context.
stylix = {
  enable = true;
  base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark.yaml";
  # ...
};
```

### Target locations

| Target | Where to enable | Notes |
|--------|----------------|-------|
| `gtk` | NixOS `stylix.targets.gtk` | System GTK theme |
| `grub` | NixOS `stylix.targets.grub` | Bootloader |
| `console` | NixOS `stylix.targets.console` | TTY colors |
| `lightdm` | NixOS `stylix.targets.lightdm` | Greeter theme |
| `fish` | HM `stylix.targets.fish` | Shell prompt colors |
| `gtk` (HM) | HM `stylix.targets.gtk` | Per-user GTK overrides |
| `i3` | HM `stylix.targets.i3` | Window border colors |
| `kitty` | HM `stylix.targets.kitty` | Terminal colors |
| `nixvim` | HM `stylix.targets.nixvim` | Neovim colorscheme |
| `firefox` | HM `stylix.targets.firefox` | Browser theme |
| `xfce` | HM `stylix.targets.xfce` | Fonts only (NOT colors) |
| `qt` | HM `stylix.targets.qt` | qtct + kvantum theme |

### Available base16 gruvbox schemes (from `pkgs.base16-schemes`)
- `gruvbox-dark.yaml` — standard dark (bg #282828)
- `gruvbox-dark-hard.yaml` — darker (bg #1d2021)
- `gruvbox-dark-medium.yaml` — medium dark (bg #282828, same as dark)
- `gruvbox-dark-pale.yaml` — paler variant
- `gruvbox-dark-soft.yaml` — softer (bg #32302f)
- `gruvbox-light.yaml` / `gruvbox-light-*.yaml` — light variants

```bash
# List all available schemes
ls $(nix eval --raw nixpkgs#base16-schemes)/share/themes/ | grep gruvbox
```

### Known Stylix bugs/workarounds

**Firefox bug #2071:** xdg-desktop-portal-gtk reads dconf color-scheme instead
of GTK theme → Firefox unstyled. Fix in `home/desktop/firefox.nix`:
```nix
{ lib, ... }: {
  dconf.settings."org/gnome/desktop/interface".color-scheme = lib.mkForce "prefer-dark";
}
```

**XFCE target:** Only sets fonts, not colors. Set terminal/panel colors manually
via `xfconf.settings` in HM (see `home/desktop/xfce-colors.nix`).

---

## sops-nix Patterns

```nix
# nixos/sops.nix — system module
sops = {
  defaultSopsFile = ../secrets/secrets.yaml;
  age.keyFile = "/var/lib/sops-nix/key.txt";   # provisioned at first boot
  secrets = {
    user-password.neededForUsers = true;
    github_ssh_key = {
      owner = "vino";
      path = "/home/vino/.ssh/github";
    };
  };
};
```

```bash
# Edit secrets (requires SOPS_AGE_KEY or gpg key in env)
sops secrets/secrets.yaml

# Rotate keys (updates .sops.yaml, re-encrypts)
sops updatekeys secrets/secrets.yaml

# Check what's decryptable
sops --decrypt --extract '["secret_name"]' secrets/secrets.yaml
```

**First-boot provisioning:** Copy the age key to `/var/lib/sops-nix/key.txt`
before `nixos-rebuild switch`. Without it, activation fails on secrets with
`neededForUsers = true`.

---

## Rebuild Commands

```bash
# Apply and make permanent (creates new generation)
sudo nixos-rebuild switch --flake .#bandit

# Apply to running session only (no new generation entry)
sudo nixos-rebuild test --flake .#bandit

# Build without applying (validates full closure)
sudo nixos-rebuild build --flake .#bandit

# Dry-run (no download, just evaluates derivation graph)
nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
  --dry-run --no-update-lock-file

# Check what changed between builds
nvd diff /run/current-system result

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

**Note:** `nixos-rebuild test` does NOT create a new generation entry. If the
generation list looks unchanged after a `test` build, that is expected.

---

## Debugging / Introspection

```bash
# What packages are in the current system closure
nix-store -qR /run/current-system | grep firefox

# What generated a specific file
nix-store -q --references /etc/gtk-3.0/settings.ini

# Evaluate a NixOS option value
nixos-option stylix.base16Scheme

# Check Home Manager generation
ls -la /nix/var/nix/profiles/per-user/vino/

# See what HM generated for the current user
ls ~/.local/share/home-manager/
ls /etc/profiles/per-user/vino/

# Check dconf values
dconf read /org/gnome/desktop/interface/color-scheme
dconf dump /org/gnome/desktop/interface/

# Check xfconf values
xfconf-query -c xfce4-terminal -lv
xfconf-query -c xfce4-panel -lv
xfconf-query -c xsettings -lv   # GTK theme name, icon theme

# Check active GTK theme
gsettings get org.gnome.desktop.interface gtk-theme
```

---

## Common NixOS Patterns

### Adding a service
```nix
# In the appropriate nixos/*.nix file
services.myservice = {
  enable = true;
  settings = { ... };
};
```

### User packages vs system packages
```nix
# System-wide (nixos/dev.nix or similar)
environment.systemPackages = with pkgs; [ git curl ];

# Per-user (home/shell.nix or similar)
home.packages = with pkgs; [ ripgrep fd ];
```

### Overlays
```nix
# In flake.nix outputs or nixpkgs import
nixpkgs.overlays = [
  (final: prev: {
    myPackage = prev.myPackage.override { ... };
  })
];
```

### Environment variables
```nix
# System-wide
environment.variables = { EDITOR = "nvim"; };
environment.sessionVariables = { BROWSER = "firefox"; };  # login sessions only

# Per-user (Home Manager)
home.sessionVariables = { EDITOR = "nvim"; };
```

---

## Formatting & Linting

```bash
# Format all .nix files (alejandra)
nix run nixpkgs#alejandra -- .

# Check formatting without modifying
nix run nixpkgs#alejandra -- --check .

# Dead code check (unused bindings, imports)
nix run nixpkgs#deadnix -- --fail .

# Static analysis (antipatterns, deprecated syntax)
nix run nixpkgs#statix -- check .

# Full pre-commit check
nix flake check --no-update-lock-file
```

---

## XDG Portals

XFCE + i3 combo requires `xdg-desktop-portal-gtk` for sandboxed apps. The
`config.common.default = "gtk"` line routes all portal requests to GTK portal:

```nix
xdg.portal = {
  enable = true;
  wlr.enable = false;   # Wayland only, not needed for X11
  extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  config.common.default = "gtk";
};
```

**Side effect:** Firefox bug #2071 — GTK portal reads dconf color-scheme to
decide dark/light mode, bypassing the actual GTK theme. Workaround: set
`dconf color-scheme = prefer-dark` (see Stylix bugs above).
