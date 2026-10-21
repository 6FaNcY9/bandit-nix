{pkgs, ...}: {
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    tmp.useTmpfs = true;
  };

  # Disable the NixOS manual — large closure not needed on a desktop.
  # Man pages stay enabled.
  documentation.nixos.enable = false;
}
