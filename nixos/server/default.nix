{
  lib,
  pkgs,
  zellijMenu,
  ...
}: {
  imports = [
    ../sops.nix
    ../cli-tools.nix
    ../core.nix
    ../boot.nix
    ../hardening.nix
    ../network.nix
    ../firmware.nix
    ../users.nix
    ./editor.nix
    ./zellij.nix
    ./zsh.nix
    ./starship.nix
  ];

  environment = {
    # ── Base server packages (no desktop/VM tools) ──────────────────────────
    systemPackages = with pkgs; [
      btop
      htop
      iotop
      lsof
      ncdu
      dnsutils
      fzf
      zoxide
      zellij
      zellijMenu
      zsh-fzf-tab
    ];

    # ── Remote access ──────────────────────────────────────────────────────
    enableAllTerminfo = true;
  };

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    nh.enable = true;
  };

  services = {
    openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Server keeps the same monthly cadence as the laptop; adjust per-host if disk churn increases.
    btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      fileSystems = ["/"];
    };
  };

  # ── Memory ────────────────────────────────────────────────────────────────
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25; # 16 GB zram out of 64 GB RAM
  };

  # ── Nix build capacity ────────────────────────────────────────────────────
  nix.settings = {
    max-jobs = 2;
    cores = 4;
  };

  # Keep more generations than the laptop's 30d (core.nix): the auto-updater's
  # rollback target must survive quiet periods with no deploys.
  nix.gc.options = lib.mkForce "--delete-older-than 90d";
}
