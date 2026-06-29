_: {
  # bandit-lab is a 24/7 headless server — prevent any suspend/sleep.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    "hybrid-sleep".enable = false;
  };

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleSuspendKey = "ignore";
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";
    IdleAction = "ignore";
  };

  # i9-14900HX on AC power: performance governor for consistent server latency.
  powerManagement.cpuFreqGovernor = "performance";
}
