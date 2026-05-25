# Theming & UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply gruvbox-dark-hard system-wide via Stylix, fix Qt theming, add Firefox, wire up CopyQ floating, and enable i3 autotiling.

**Architecture:** All changes are declarative NixOS/Home Manager config edits. No new flake inputs are needed. Validation at each task is `nix flake check` + dry-run build; final step is `nixos-rebuild test`.

**Tech Stack:** NixOS unstable, Home Manager, Stylix (danth/stylix), nixvim, i3, alejandra (formatter)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `home/theme.nix` | Modify | Enable nixvim, firefox, i3 Stylix targets |
| `home/editor.nix` | Modify | Remove native gruvbox colorscheme; set lualine theme to auto |
| `nixos/core.nix` | Modify | Enable LightDM Stylix target |
| `nixos/desktop.nix` | Modify | Add Qt platformTheme → GTK |
| `home/desktop/i3.nix` | Modify | CopyQ float rule; autotiling package + startup |
| `home/desktop/firefox.nix` | Create | `programs.firefox.enable = true` |
| `home/default.nix` | Modify | Import `./desktop/firefox.nix` |

---

## Validation commands (run after every task)

```bash
# Lint
nix flake check --no-update-lock-file
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .

# Dry-run build (validates the full closure without downloading)
nix build .#nixosConfigurations.bandit.config.system.build.toplevel \
  --dry-run --no-update-lock-file
```

---

### Task 1: Enable Stylix targets for nixvim, i3, and Firefox

**Files:**
- Modify: `home/theme.nix`

Current content of `home/theme.nix`:
```nix
_: {
  stylix.targets = {
    fish.enable = true;
    gtk.enable = true;
    xfce.enable = true;
    kitty.enable = true;
    nixvim.enable = false;
  };
}
```

- [ ] **Step 1: Update home/theme.nix**

Replace the entire file with:
```nix
_: {
  stylix.targets = {
    fish.enable = true;
    gtk.enable = true;
    xfce.enable = true;
    kitty.enable = true;
    nixvim.enable = true;
    i3.enable = true;
    firefox.enable = true;
  };
}
```

- [ ] **Step 2: Lint and dry-run**

```bash
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --dry-run --no-update-lock-file
```

Expected: exits 0 on all four commands.

- [ ] **Step 3: Commit**

```bash
git add home/theme.nix
git commit -m "stylix: enable nixvim, i3, and firefox targets"
```

---

### Task 2: Remove native gruvbox colorscheme from nvim, fix lualine

**Files:**
- Modify: `home/editor.nix`

When Stylix manages nixvim (`nixvim.enable = true`), it injects the base16 colorscheme
via `base16-vim`. The native `colorschemes.gruvbox` block must be removed to avoid a
conflict, and lualine's `theme` must change from `"gruvbox"` (a named plugin theme) to
`"auto"` (lualine auto-detects the active colorscheme).

- [ ] **Step 1: Remove colorschemes.gruvbox block from home/editor.nix**

Find and delete lines 8–14 in `home/editor.nix`:
```nix
    colorschemes.gruvbox = {
      enable = true;
      settings = {
        contrast_dark = "hard";
        transparent_bg = false;
      };
    };
```

- [ ] **Step 2: Change lualine theme from "gruvbox" to "auto"**

Find in `home/editor.nix` (around line 287):
```nix
      lualine = {
        enable = true;
        settings.options.theme = "gruvbox";
      };
```

Replace with:
```nix
      lualine = {
        enable = true;
        settings.options.theme = "auto";
      };
```

- [ ] **Step 3: Lint and dry-run**

```bash
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --dry-run --no-update-lock-file
```

Expected: exits 0 on all four commands.

- [ ] **Step 4: Commit**

```bash
git add home/editor.nix
git commit -m "editor: remove native gruvbox colorscheme, let stylix manage nvim colors"
```

---

### Task 3: LightDM Stylix target

**Files:**
- Modify: `nixos/core.nix`

LightDM is the login screen manager. Without a Stylix target it renders a plain white
greeter. Adding `targets.lightdm.enable = true` tells Stylix to apply gruvbox-dark-hard
colors and fonts to the GTK greeter.

- [ ] **Step 1: Add lightdm target to nixos/core.nix**

Find in `nixos/core.nix`:
```nix
    targets = {
      gtk.enable = true;
      grub.enable = true;
      console.enable = true;
    };
```

Replace with:
```nix
    targets = {
      gtk.enable = true;
      grub.enable = true;
      console.enable = true;
      lightdm.enable = true;
    };
```

- [ ] **Step 2: Lint and dry-run**

```bash
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --dry-run --no-update-lock-file
```

Expected: exits 0 on all four commands.

- [ ] **Step 3: Commit**

```bash
git add nixos/core.nix
git commit -m "stylix: theme lightdm login screen with gruvbox-dark-hard"
```

---

### Task 4: Qt theming

**Files:**
- Modify: `nixos/desktop.nix`

Qt applications (CopyQ, and any future Qt tool) receive no theme from Stylix because
Stylix only manages GTK. Adding `qt.platformTheme.name = "gtk"` tells Qt5/Qt6 apps to
pull their widget style and palette from the active GTK theme, which Stylix manages as
gruvbox-dark-hard.

- [ ] **Step 1: Add Qt config to nixos/desktop.nix**

Open `nixos/desktop.nix`. At the top level of the returned attrset (after the closing
`};` of `services` and before the final `}`), add:

```nix
  qt = {
    enable = true;
    platformTheme.name = "gtk";
  };
```

The end of the file should look like:
```nix
  # Polkit for privilege escalation in GUI apps (e.g. software updater)
  security.polkit.enable = true;

  # Needed for XFCE settings daemon and GTK apps
  programs.dconf.enable = true;
  hardware.acpilight.enable = true;

  # XDG portals for sandboxed apps (flatpak, snap, etc.)
  xdg.portal = {
    enable = true;
    wlr.enable = false;
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
    config.common.default = "gtk";
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
  };
}
```

- [ ] **Step 2: Lint and dry-run**

```bash
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --dry-run --no-update-lock-file
```

Expected: exits 0 on all four commands.

- [ ] **Step 3: Commit**

```bash
git add nixos/desktop.nix
git commit -m "desktop: add Qt GTK platform theme so Qt apps follow stylix colors"
```

---

### Task 5: CopyQ floating rule and i3 autotiling

**Files:**
- Modify: `home/desktop/i3.nix`

Two independent fixes in one file:
1. CopyQ needs a floating rule — its i3 window class is `copyq` (lowercase).
2. `i3-autotiling` watches the focused window and automatically chooses horizontal or
   vertical split based on the container's aspect ratio.

- [ ] **Step 1: Add copyq to floating criteria**

Find in `home/desktop/i3.nix`:
```nix
        floating = {
          modifier = mod;
          criteria = [
            {class = "Pavucontrol";}
            {class = "Blueman-manager";}
            {class = "flameshot";}
            {title = "Picture-in-Picture";}
          ];
        };
```

Replace with:
```nix
        floating = {
          modifier = mod;
          criteria = [
            {class = "Pavucontrol";}
            {class = "Blueman-manager";}
            {class = "flameshot";}
            {class = "copyq";}
            {title = "Picture-in-Picture";}
          ];
        };
```

- [ ] **Step 2: Replace the entire startup list in home/desktop/i3.nix**

Find:
```nix
      startup = [
        # Lock screen automatically before suspend.
        {
          command = "${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${pkgs.i3lock}/bin/i3lock -c 262626 -n";
          notification = false;
        }
        {
          command = "${pkgs.dunst}/bin/dunst";
          notification = false;
        }
        {
          command = "${pkgs.networkmanagerapplet}/bin/nm-applet";
          notification = false;
        }
        {
          command = "${pkgs.blueman}/bin/blueman-applet";
          notification = false;
        }
        {
          command = "${pkgs.copyq}/bin/copyq";
          notification = false;
        }
        # XFCE panel — provides system tray since you're running XFCE+i3
        {
          command = "${pkgs.xfce4-panel}/bin/xfce4-panel --disable-wm-check";
          notification = false;
        }
      ];
```

Replace with:
```nix
      startup = [
        {
          command = "${pkgs.i3-autotiling}/bin/i3-autotiling";
          notification = false;
        }
        # Lock screen automatically before suspend.
        {
          command = "${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${pkgs.i3lock}/bin/i3lock -c 262626 -n";
          notification = false;
        }
        {
          command = "${pkgs.dunst}/bin/dunst";
          notification = false;
        }
        {
          command = "${pkgs.networkmanagerapplet}/bin/nm-applet";
          notification = false;
        }
        {
          command = "${pkgs.blueman}/bin/blueman-applet";
          notification = false;
        }
        {
          command = "${pkgs.copyq}/bin/copyq";
          notification = false;
        }
        # XFCE panel — provides system tray since you're running XFCE+i3
        {
          command = "${pkgs.xfce4-panel}/bin/xfce4-panel --disable-wm-check";
          notification = false;
        }
      ];
```

- [ ] **Step 3: Add i3-autotiling to home.packages**

Find in `home/desktop/i3.nix`:
```nix
  home.packages = with pkgs; [
    rofi
    flameshot
    xss-lock
    dunst
    copyq
    playerctl
    brightnessctl
    pulseaudio # for pactl
    networkmanagerapplet
  ];
```

Replace with:
```nix
  home.packages = with pkgs; [
    rofi
    flameshot
    xss-lock
    dunst
    copyq
    playerctl
    brightnessctl
    pulseaudio # for pactl
    networkmanagerapplet
    i3-autotiling
  ];
```

- [ ] **Step 4: Lint and dry-run**

```bash
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --dry-run --no-update-lock-file
```

Expected: exits 0 on all four commands.

- [ ] **Step 5: Commit**

```bash
git add home/desktop/i3.nix
git commit -m "i3: add copyq floating rule and enable autotiling"
```

---

### Task 6: Firefox

**Files:**
- Create: `home/desktop/firefox.nix`
- Modify: `home/default.nix`

`programs.firefox.enable = true` is required for Stylix's firefox target (enabled in
Task 1) to activate — Stylix injects a `userChrome.css` with base16 color overrides
only when the HM firefox module is loaded.

- [ ] **Step 1: Create home/desktop/firefox.nix**

```nix
_: {
  programs.firefox.enable = true;
}
```

- [ ] **Step 2: Add import to home/default.nix**

Find in `home/default.nix`:
```nix
    ./desktop/i3.nix
    ./editor.nix
```

Replace with:
```nix
    ./desktop/i3.nix
    ./desktop/firefox.nix
    ./editor.nix
```

- [ ] **Step 3: Lint and dry-run**

```bash
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
nix build .#nixosConfigurations.bandit.config.system.build.toplevel --dry-run --no-update-lock-file
```

Expected: exits 0 on all four commands.

- [ ] **Step 4: Commit**

```bash
git add home/desktop/firefox.nix home/default.nix
git commit -m "firefox: add HM module so stylix firefox target can inject gruvbox theme"
```

---

### Task 7: Apply and verify on running system

- [ ] **Step 1: Final lint pass**

```bash
nix flake check --no-update-lock-file
nix run nixpkgs#alejandra -- --check .
nix run nixpkgs#deadnix -- --fail .
nix run nixpkgs#statix -- check .
```

Expected: all exit 0.

- [ ] **Step 2: Apply with test (survives reboot rollback)**

```bash
sudo nixos-rebuild test --flake .#bandit
```

Expected: builds and switches without errors.

- [ ] **Step 3: Visual verification checklist**

- [ ] Open kitty → nvim: background color matches terminal background exactly
- [ ] Open CopyQ via `Super+Shift+V`: appears as floating window (not tiled)
- [ ] Open a new kitty window and a Firefox window side by side: autotiling splits them automatically
- [ ] Reboot: LightDM login screen shows dark gruvbox background instead of white
- [ ] Open any Qt app (e.g. `copyq`): no white flash, dark theme throughout
- [ ] Firefox opens and chrome/tabs area has dark gruvbox colors

- [ ] **Step 4: If everything looks good, make permanent**

```bash
sudo nixos-rebuild switch --flake .#bandit
```
