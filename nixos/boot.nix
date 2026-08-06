{pkgs, ...}: {
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    tmp.useTmpfs = true;
  };

  # Disable NixOS documentation — large closure not needed on a desktop.
  documentation = {
    enable = true;
    nixos.enable = true;
    man.enable = true;
  };
}
