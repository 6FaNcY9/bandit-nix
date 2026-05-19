_: {
  services = {
    fwupd.enable = true;
    fprintd.enable = true;
    # upower provides battery status used by status bars (xfce4-panel)
    # and desktop environments to show charge level and power state.
    upower.enable = true;
  };

  # AMD CPU microcode updates — applied at boot for security and stability.
  hardware.cpu.amd.updateMicrocode = true;

  # Redistributable firmware blobs for WiFi (ath11k) and Bluetooth.
  # Required for reliable wireless on the Framework 13 AMD.
  hardware.enableRedistributableFirmware = true;
}
