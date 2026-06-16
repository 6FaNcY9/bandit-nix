{pkgs, ...}: {
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    tmp.useTmpfs = true;
  };

  # Disable NixOS documentation — large closure not needed on a desktop.
  documentation = {
    enable = false;
    nixos.enable = false;
    man.enable = true;
  };
}
