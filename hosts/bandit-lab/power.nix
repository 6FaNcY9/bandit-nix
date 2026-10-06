{pkgs, ...}: {
  # bandit-lab is a 24/7 headless server — prevent any suspend/sleep.
  systemd = {
    targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      "hybrid-sleep".enable = false;
    };

    # Energy-performance preference for intel_pstate (HWP): "balance_performance"
    # keeps latency good for a 24/7 server without pinning clocks high on a
    # laptop chassis. The kernel applies it per core; the `*` glob covers all of
    # them (tmpfiles `w` accepts shell-style globs).
    tmpfiles.rules = [
      "w /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference - - - - balance_performance"
    ];

    services.disable-console-blanking = {
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

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleSuspendKey = "ignore";
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";
    IdleAction = "ignore";
  };

  # i9-14900HX in a laptop chassis, always on AC, running 24/7. With
  # intel_pstate in active/HWP mode the `powersave` governor still lets the CPU
  # boost on demand (the hardware picks the frequency); `performance` would keep
  # clocks high and the chassis hot all day. Observed on the live lab
  # (2026-10-06): governor powersave and preference balance_power although this
  # file used to ask for `performance`, so the old setting was not what ran.
  # Measure the effect: `sudo turbostat --quiet --interval 10 --num_iterations 6
  # --show PkgWatt,Busy%,Bzy_MHz` at idle and under load, and watch the blackbox
  # probe latencies in Grafana.
  powerManagement.cpuFreqGovernor = "powersave";
}
