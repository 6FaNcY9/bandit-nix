{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./sops.nix
    ./core.nix
    ./boot.nix
    ./network.nix
    ./firmware.nix
    ./users.nix
  ];

  environment = {
    # ── Base server packages (no desktop/VM tools) ──────────────────────────
    systemPackages = with pkgs; [
      git
      curl
      wget
      jq
      ripgrep
      fd
      bat
      eza
      gnupg
      tree-sitter
      gnumake
      pkg-config
      usbutils
      pciutils
      lm_sensors
      alejandra
      deadnix
      statix
      nix-output-monitor
      nvd
      sops
      cachix
      btop
      htop
      iotop
      lsof
      ncdu
      dnsutils
      fzf
      zoxide
      zellij
      brightnessctl
      libinput
    ];

    etc."xdg/zellij/config.kdl".text = ''
      theme "gruvbox-dark"
      pane_frames true
      default_layout "compact"

      themes {
          gruvbox-dark {
              fg 213 196 161
              bg 40 40 40
              black 40 40 40
              red 204 36 29
              green 152 151 26
              yellow 215 153 33
              blue 69 133 136
              magenta 177 98 134
              cyan 104 157 106
              white 213 196 161
              orange 214 93 14
          }
      }
    '';

    # ── Remote access ──────────────────────────────────────────────────────
    enableAllTerminfo = true;
  };

  programs = {
    zsh = {
      interactiveShellInit = ''
        # Keep console/SSH editing sane even when the terminal reports odd keys.
        stty erase '^?' 2>/dev/null || true
        bindkey -e
        bindkey '^?' backward-delete-char
        bindkey '^H' backward-delete-char
        bindkey '^[[3~' delete-char
        bindkey '^[[H' beginning-of-line
        bindkey '^[[F' end-of-line
        bindkey '^[[1;5D' backward-word
        bindkey '^[[1;5C' forward-word

        [[ -r ${pkgs.fzf}/share/fzf/key-bindings.zsh ]] && source ${pkgs.fzf}/share/fzf/key-bindings.zsh
        command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

        zj() {
          ZELLIJ_CONFIG_DIR=/etc/xdg/zellij zellij attach "''${1:-main}" --create
        }

        zjh() {
          print "zellij quick help"
          print "  zj [name]     attach/create a zellij session"
          print "  Ctrl-g ?      show zellij keybinding help"
          print "  Ctrl-g p/n    previous/next pane"
          print "  Ctrl-g t      new tab"
          print "  Ctrl-g d      detach"
        }

        if [[ $- == *i* && $SHLVL -eq 1 ]]; then
          print ""
          print "bandit-lab TTY · run 'zj' for the terminal workspace · run 'zjh' for keys"
          print ""
        fi
      '';

      ohMyZsh = {
        enable = true;
        plugins = [
          "colored-man-pages"
          "command-not-found"
          "extract"
          "git"
          "history-substring-search"
          "sudo"
          "systemd"
        ];
        theme = "robbyrussell";
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    nh.enable = true;
  };

  fonts.packages = [pkgs.nerd-fonts.jetbrains-mono];

  # Blank the local console after 5 minutes without keyboard/mouse input.
  boot.kernelParams = ["consoleblank=300"];

  # ── TTY-only server surface ───────────────────────────────────────────────
  services = {
    xserver = {
      enable = false;
      displayManager.lightdm.enable = false;
      desktopManager.xfce.enable = false;
      windowManager.i3.enable = false;
    };

    blueman.enable = lib.mkForce false;
    gnome.gnome-keyring.enable = lib.mkForce false;

    kmscon = {
      enable = true;
      useXkbConfig = true;
      config = {
        "font-name" = "JetBrainsMono Nerd Font Mono";
        "font-size" = 18;
        hwaccel = false;
      };
    };
  };

  hardware.bluetooth.enable = lib.mkForce false;
  security.pam.services.greetd.enableGnomeKeyring = lib.mkForce false;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  systemd.services.server-screen-idle = {
    description = "Turn off the laptop panel backlight after local input idle";
    wantedBy = ["multi-user.target"];
    after = ["systemd-udevd.service"];
    path = with pkgs; [
      brightnessctl
      coreutils
      libinput
    ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
    };
    script = ''
      set -euo pipefail

      idle_seconds=300
      state_dir=/run/server-screen-idle
      mkdir -p "$state_dir"

      restore_screen() {
        local saved name value
        for saved in "$state_dir"/*.brightness; do
          [[ -e "$saved" ]] || continue
          read -r name value < "$saved" || continue
          brightnessctl -q -d "$name" set "$value" || true
          rm -f "$saved"
        done
      }

      dim_screen() {
        local dev name current
        for dev in /sys/class/backlight/*; do
          [[ -e "$dev" ]] || continue
          name="$(basename "$dev")"
          current="$(brightnessctl -d "$name" get 2>/dev/null || true)"
          [[ -n "$current" && "$current" -gt 0 ]] || continue
          printf '%s %s\n' "$name" "$current" > "$state_dir/$name.brightness"
          brightnessctl -q -d "$name" set 0 || true
        done
      }

      trap restore_screen EXIT

      last_input="$(date +%s)"
      screen_dimmed=0

      while true; do
        if read -r -t 5 _event; then
          last_input="$(date +%s)"
          if [[ "$screen_dimmed" -eq 1 ]]; then
            restore_screen
            screen_dimmed=0
          fi

          while read -r -t 0 _event; do
            last_input="$(date +%s)"
          done
        fi

        now="$(date +%s)"
        if [[ "$screen_dimmed" -eq 0 && $((now - last_input)) -ge "$idle_seconds" ]]; then
          dim_screen
          screen_dimmed=1
        fi
      done < <(libinput debug-events --udev --show-keycodes)
    '';
  };

  # ── Memory ────────────────────────────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25; # 16 GB zram out of 64 GB RAM
  };

  # ── BTRFS maintenance ─────────────────────────────────────────────────────
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = ["/"];
  };

  # ── Nix build capacity ────────────────────────────────────────────────────
  nix.settings = {
    max-jobs = 16; # i9 — adjust to actual core count after nixos-generate-config
    cores = 0;
  };
}
