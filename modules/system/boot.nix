{pkgs, ...}: {
  boot = {
    # shortcut: sign framework-laptop-kmod by hand until nixpkgs#575818 (modules_install) reaches nixos-unstable; drop then.
    kernelPackages = pkgs.linuxPackages_latest.extend (_: super: {
      framework-laptop-kmod = super.framework-laptop-kmod.overrideAttrs {
        postInstall = "${pkgs.lib.getExe pkgs.buildPackages.kmodigest} $out/lib/modules/${super.kernel.modDirVersion}/extra/framework_laptop.ko";
      };
    });
    tmp.useTmpfs = true;
  };

  # Disable the NixOS manual — large closure not needed on a desktop.
  # Man pages stay enabled.
  documentation.nixos.enable = false;
}
