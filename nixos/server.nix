{pkgs, ...}: {
  imports = [
    ./sops.nix
    ./core.nix
    ./boot.nix
    ./network.nix
    ./firmware.nix
    ./users.nix
  ];

  # ── Base server packages (no desktop/VM tools) ────────────────────────────
  environment.systemPackages = with pkgs; [
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
  ];

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
      '';

      ohMyZsh = {
        enable = true;
        plugins = [
          "git"
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

  # ── Remote access ────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
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
