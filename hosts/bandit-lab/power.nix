{pkgs, ...}: {
  # bandit-lab is a 24/7 headless server — prevent any suspend/sleep.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    "hybrid-sleep".enable = false;
  };

  # ── Console blanking ──────────────────────────────────────────────────────
  # The built-in eDP panel hangs off the NVIDIA GPU, which is this host's only
  # DRM device. When the console blanker powers the panel down it does not come
  # back on keypress: the connector stays `enabled` and fbcon still reports
  # `blank = 0` while DPMS sits at `Off`, so the physical console looks frozen
  # even though the machine is healthy and SSH keeps working.
  #
  # Belt and braces, because these apply at different times:
  #   - kernelParams wins from boot, but only after a reboot.
  #   - the unit below applies on plain `switch-to-configuration switch`, which
  #     is all lab-update ever runs — without it a kernel-param-only fix sits
  #     dormant until someone happens to reboot.
  boot.kernelParams = ["consoleblank=0"];

  systemd.services.disable-console-blanking = {
    description = "Disable virtual console blanking on tty1";
    wantedBy = ["multi-user.target"];
    after = ["getty@tty1.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TTYPath = "/dev/tty1";
      StandardOutput = "tty";
      Environment = "TERM=linux";
      ExecStart = "${pkgs.util-linux}/bin/setterm --blank 0 --powersave off";
    };
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
