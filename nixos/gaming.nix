{pkgs, ...}: {
  # Steam + Proton gaming stack for bandit (Radeon 780M, Hyprland/Wayland).
  # 32-bit graphics drivers are already enabled in nixos/graphics.nix.
  programs = {
    steam = {
      enable = true;
      # Steam Input via uinput on Wayland (Hyprland).
      extest.enable = true;
      protontricks.enable = true;
      # Proton-GE: better game compatibility than stock Proton. Select
      # "GE-Proton" per-game in Steam -> Properties -> Compatibility.
      extraCompatPackages = [pkgs.proton-ge-bin];
      remotePlay.openFirewall = false;
      localNetworkGameTransfers.openFirewall = false;
      # Enables a gamescope-driven Steam session at the greeter and makes
      # gamescope usable per-game via launch options.
      gamescopeSession.enable = true;
    };

    gamescope = {
      enable = true;
      capSysNice = true;
    };

    gamemode = {
      enable = true;
      enableRenice = true;
    };
  };

  # udev rules for Steam Controller and other gamepads.
  hardware.steam-hardware.enable = true;

  # FPS/frametime overlay: prefix launch options with `mangohud`.
  environment.systemPackages = [pkgs.mangohud];
}
