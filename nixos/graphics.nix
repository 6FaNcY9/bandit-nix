{pkgs, ...}: {
  # amd_pstate=active enables the modern AMD P-state driver for the
  # Ryzen 7040 series iGPU/CPU — better power efficiency than acpi-cpufreq.
  boot.kernelParams = ["amd_pstate=active"];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
      libva
      libvdpau-va-gl
      mesa.opencl
    ];
  };

  environment.variables.AMD_VULKAN_ICD = "RADV";
}
