{
  lib,
  pkgs,
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
    ./zsh.nix
    ./starship.nix
  ];

  # bandit-lab decrypts only secrets/lab.yaml (recipients: user + lab host key).
  sops.defaultSopsFile = ../../secrets/lab.yaml;

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
      zsh-fzf-tab
    ];

    # ── Remote access ──────────────────────────────────────────────────────
    enableAllTerminfo = true;
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [22];

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
      # Not opened globally: port 22 is allowed on tailscale0 only (below), so
      # the home LAN and anything else cannot reach sshd. Recovery if Tailscale
      # is down is the machine's own keyboard and screen
      # (docs/runbooks/bandit-lab-updates.md); bandit-lab-health refuses a
      # deployment that leaves Tailscale not running.
      openFirewall = false;
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
