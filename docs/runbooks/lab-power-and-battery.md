# bandit-lab power tuning and battery

## CPU governor and energy preference

Observed on the live lab (2026-10-06): all 32 cores on the `powersave` governor
with energy-performance preference `balance_power` (intel_pstate in active mode
with HWP), although the repository asked for `performance` and
`cpufreq.service` had finished successfully. So the old setting was not what ran.

Decision (hardening plan, phase 7): keep `powersave` (under intel_pstate/HWP it
still boosts on demand) and set the preference to `balance_performance` on every
core (`hosts/bandit-lab/power.nix`). That keeps request latency good on a 24/7
server in a laptop chassis without pinning clocks high.

Measure before and after (on the lab, as root):

```bash
# package power and frequency, idle then under a build or load test
sudo turbostat --quiet --interval 10 --num_iterations 6 --show PkgWatt,Busy%,Bzy_MHz
# latency of the public sites: Grafana, "Public endpoint probe" panels (blackbox)
# current setting on every core:
cat /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference | sort | uniq -c
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c
```

If idle package power rises noticeably or latency does not improve, change the
rule back to `balance_power` in `hosts/bandit-lab/power.nix` (a one-word edit).

## Battery charge limit: not configured

The lab is plugged in 24/7. Findings (2026-10-06):

- Chassis: PCSpecialist Recoil VIII 17 with a TongFang `GM7IX9N` board.
- The battery (`BAT0`) exposes no `charge_control_end_threshold` or similar
  attribute. The firmware reports "Not charging" at 95 %.
- The running kernel is built without the Uniwill platform driver
  (`CONFIG_X86_PLATFORM_DRIVERS_UNIWILL` is not set); no `uniwill`/`tuxedo`
  modules exist for it.
- The kernel mailing-list posting that adds charge-limit support to
  `uniwill-laptop` names no board lists, and warns that forcing the driver on a
  laptop that does not implement the interface properly might damage the
  battery. `tuxedo-drivers` is packaged in nixpkgs (4.20.1), but no source
  checked confirms that it supports this board or its charge control.

Per the hardening plan, a configuration is proposed only when a primary source
confirms it, so none was added. What would change this: an upstream driver or
`tuxedo-drivers` release that lists the `GM7IX9N` board, a vendor BIOS/EC
battery-care option, or a smart plug that cuts power at a chosen charge level.
Until then, a battery that sits at 100 % on AC for years will lose capacity; the
lab does not depend on the battery for operation.
