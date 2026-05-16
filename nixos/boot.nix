{ pkgs, ... }:
{
  boot = {
    loader = {
      grub = {
        enable = true;
        device = "nodev";        # for EFI systems
        efiSupport = true;
        useOSProber = true;      # detects Windows/other OS on dual boot
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
    tmp.useTmpfs = true;
  };

  security.rtkit.enable = true;
}
