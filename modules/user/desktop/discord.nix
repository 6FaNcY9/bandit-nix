{pkgs, ...}: {
  # Vesktop instead of the official client: free (no unfree entry) and screen sharing works on Wayland/Hyprland.
  home.packages = [pkgs.vesktop];
}
