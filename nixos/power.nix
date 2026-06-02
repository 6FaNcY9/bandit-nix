_: {
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  services = {
    power-profiles-daemon.enable = true;
    fstrim.enable = true;
    btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      fileSystems = ["/"];
    };
    logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
      HandlePowerKey = "ignore";
      HandlePowerKeyLongPress = "poweroff";
      IdleAction = "suspend";
      IdleActionSec = "15min";
    };
  };

  powerManagement.enable = true;
}
