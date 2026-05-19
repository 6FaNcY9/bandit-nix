{pkgs, ...}: {
  boot = {
    loader = {
      grub = {
        enable = true;
        device = "nodev"; # for EFI systems
        efiSupport = true;
        useOSProber = true; # detects Windows/other OS on dual boot
        configurationLimit = 10;
        # Disable splash image to avoid pulling in nixos-icons (~500MB
        # of historical NixOS artwork) which causes CI disk space failures.
        splashImage = null;
      };
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = ["mem_sleep_default=s2idle"];
    tmp.useTmpfs = true;
  };

  security.rtkit.enable = true;

  # Disable NixOS documentation — large closure not needed on a desktop.
  documentation = {
    enable = false;
    nixos.enable = false;
    man.enable = true; # keep man pages
  };
}
