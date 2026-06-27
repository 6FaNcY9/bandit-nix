{lib, ...}: {
  imports = [
    ./hardware.nix
  ];

  networking.hostName = "bandit";
  system.stateVersion = "25.11";

  # ── Bootloader (GRUB + EFI) ───────────────────────────────────────────────
  boot.loader = {
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      useOSProber = false;
      configurationLimit = 10;
      # Stylix also sets splashImage — mkForce prevents conflict.
      # Disabled to avoid pulling nixos-icons (~500MB) in CI builds.
      splashImage = lib.mkForce null;
    };
    efi.canTouchEfiVariables = true;
  };

  # Framework 13 AMD 7040: s2idle is the only working suspend mode.
  boot.kernelParams = ["mem_sleep_default=s2idle"];

  # ── Programs ───────────────────────────────────────────────
  programs = {
    nix-ld.enable = true;
  };
}
