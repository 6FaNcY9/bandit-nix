# bandit-lab kernel/GPU contract (hardening phase 6, decision D8): the lab runs
# the default LTS kernel, not linuxPackages_latest, with the open NVIDIA kernel
# modules built against it. Evaluation-time assertions only.
{
  pkgs,
  lib,
  lab,
}: let
  kernel = lab.boot.kernelPackages;
  nvidia = kernel.nvidiaPackages.stable;
in
  assert lib.assertMsg (kernel.kernel.version == pkgs.linuxPackages.kernel.version)
  "bandit-lab must run the default LTS kernel (${pkgs.linuxPackages.kernel.version}), not ${kernel.kernel.version}";
  assert lib.assertMsg lab.hardware.nvidia.open "bandit-lab must use the open NVIDIA kernel modules";
  assert lib.assertMsg (!(nvidia.meta.broken or false)) "the NVIDIA driver is marked broken for kernel ${kernel.kernel.version}";
    pkgs.writeText "lab-kernel" "kernel ${kernel.kernel.version}, nvidia ${nvidia.version}\n"
