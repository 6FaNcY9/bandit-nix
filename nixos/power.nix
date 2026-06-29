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

  # Limit charge to 80% to extend battery longevity when frequently plugged in.
  # Adjust threshold if longer range is needed.
  systemd.tmpfiles.rules = [
    "w /sys/class/power_supply/BAT1/charge_control_end_threshold - - - - 80"
  ];
}
