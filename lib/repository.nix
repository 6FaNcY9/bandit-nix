{lib}: let
  unfreePackageNames = [
    "cheatsheet.nvim"
    "nvidia-kernel-modules"
    "nvidia-persistenced"
    "nvidia-settings"
    "obsidian"
    "nvidia-x11"
    "copilot-language-server"
    "steam"
    "steam-original"
    "steam-unwrapped"
    "steam-run"
    # Vendored in pkgs/anisette-v3-server; upstream ships no LICENSE file.
    "anisette-v3-server"
  ];
in {
  system = "x86_64-linux";

  workstation = {
    username = "vino";
    homeDirectory = "/home/vino";
    repoPath = "/home/vino/src/bandit-nix";
  };

  lab = {
    # Tailscale IP of bandit-lab. Update after any Tailscale machine
    # re-enrollment or tailnet migration.
    tailscaleIp = "100.125.161.81";
    # Tailscale IP of the owner laptop `bandit`; BotGate (Minecraft Velocity
    # proxy) lets bot1..bot99 skip Mojang login from this address only.
    workstationTailscaleIp = "100.102.247.30";
    # MagicDNS name of bandit-lab and the HTTPS port `tailscale serve` uses for
    # the mcbots hub (remote workers; the dashboard is on 8445).
    tailnetFqdn = "bandit-lab.tail7facc9.ts.net";
    mcbotsWorkerServePort = 8446;
  };

  # Peer backups: bandit and bandit-lab each run a restic REST server on their
  # own tailnet address and push to the other (docs/runbooks/backup-peer.md).
  backupPeer = {
    port = 8000;
    # restic forget policy shared by the Backblaze job and both peer repos.
    retention = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
      "--keep-yearly 2"
    ];
  };

  # The single colour source (themes/palette.nix) and its derived forms.
  palette = import ../themes/palette.nix;
  # "#rrggbb" base16 for the lab's shell, editor, Cockpit and Vaultwarden.
  serverPalette = (import ../themes/palette.nix).base16Hashed "dark";

  inherit unfreePackageNames;

  # Inspect-then-create Docker network as a oneshot systemd unit. A plain
  # `docker network create ... || true` would mask real daemon failures,
  # leaving dependent container units to fail later with an obscure
  # "network not found". Used for proxy/aiia on bandit-lab.
  mkDockerNetwork = pkgs: name: let
    script = pkgs.writeShellScript "ensure-${name}-network" ''
      set -euo pipefail
      if ! ${pkgs.docker}/bin/docker network inspect ${name} >/dev/null 2>&1; then
        ${pkgs.docker}/bin/docker network create ${name}
      fi
    '';
  in {
    description = "Create ${name} Docker network";
    after = ["docker.service"];
    requires = ["docker.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = script;
    };
  };

  allowUnfreePredicate = pkg: let
    name = lib.getName pkg;
  in
    builtins.elem name unfreePackageNames
    # The NVIDIA driver closure needs cuda_nvml_dev, whose package name is
    # versioned independently by nixpkgs.
    || lib.hasPrefix "cuda_" name;

  # Stylix for the laptop. `variant` picks scheme and polarity together, so the
  # light specialisation is one argument instead of paired mkForce overrides.
  mkStylixTheme = pkgs: variant: let
    pal = import ../themes/palette.nix;
    c = pal.variants.${variant};
  in {
    enable = true;
    base16Scheme = pal.base16 variant;
    polarity = variant;
    # Flat canvas with a faint scanline grid, generated from the palette so the
    # wallpaper follows the variant instead of being a fixed image.
    image = pkgs.runCommandLocal "bandit-wallpaper-${variant}.png" {nativeBuildInputs = [pkgs.imagemagick];} ''
      magick -size 2880x1920 xc:'#${c.grey.g0}' \
        -fill '#${c.grey.g1}' -draw "$(for y in $(seq 0 4 1920); do printf 'line 0,%d 2880,%d ' "$y" "$y"; done)" \
        -fill none -stroke '#${c.grey.g3}' -strokewidth 1 -draw "rectangle 40,40 2840,1880" \
        "$out"
    '';
    # Monospace everywhere on purpose: the desktop is a terminal-first retro
    # console. Departure Mono-style pixel fonts were tried; FiraCode stays for
    # its ligatures and Nerd Font glyphs.
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font";
      };
      serif = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font";
      };
      sizes = {
        terminal = 18;
        applications = 18;
        desktop = 18;
        # Readable rofi/mako/tooltip text on the Framework 13's high-DPI panel at scale 1.
        popups = 14;
      };
    };
    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 20;
    };
    # Papirus with grey folders matches the neutral ramp.
    icons = {
      enable = true;
      package = pkgs.papirus-icon-theme.override {color = "grey";};
      dark = "Papirus-Dark";
      light = "Papirus-Light";
    };
  };
}
