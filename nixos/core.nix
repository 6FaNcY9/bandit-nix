{
  lib,
  pkgs,
  ...
}: {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "cheatsheet.nvim"
      "cuda_nvml_dev"
      "nvidia-kernel-modules"
      "nvidia-persistenced"
      "nvidia-settings"
      "nvidia-x11"
    ];
  environment.systemPackages = with pkgs; [
    bubblewrap
  ];

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Vienna";

  console = {
    keyMap = "de-latin1-nodeadkeys";
    font = "Lat2-Terminus16";
    earlySetup = true;
  };

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      allowed-users = ["vino"];
      trusted-users = ["root" "vino"];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise = {
      automatic = true;
      dates = ["weekly"];
    };
  };

  services.journald.extraConfig = "SystemMaxUse=500M";
}
