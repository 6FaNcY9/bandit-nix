{ ... }:
{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
        consoleMode = "auto";
      };
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
    tmp.useTmpfs = true;
  };

  security.rtkit.enable = true;
}
