{pkgs, ...}: {
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
