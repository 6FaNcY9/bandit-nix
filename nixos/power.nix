_: {
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  services = {
    earlyoom = {
      enable = true;
      enableNotifications = true;
      # Act while the desktop is still responsive and zram can absorb bursts.
      freeMemThreshold = 15;
      freeSwapThreshold = 15;
      freeMemKillThreshold = 8;
      freeSwapKillThreshold = 8;
      # Kill the actual runaway process, not a smaller process with a higher
      # kernel OOM score.
      extraArgs = ["--sort-by-rss"];
    };
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
