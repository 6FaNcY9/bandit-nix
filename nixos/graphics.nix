{pkgs, ...}: {
  # amd_pstate=active is set by nixos-hardware framework-13-7040-amd module.
  # Do not set it here to avoid duplicate in /proc/cmdline.

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
