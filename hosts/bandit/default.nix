{
  lib,
  repoConfig,
  ...
}: {
  imports = [
    ./hardware.nix
  ];

  networking.hostName = "bandit";
  system.stateVersion = "25.11";

  # Laptop-only: passwordless nixos-rebuild for quick iteration
  security.sudo.extraConfig = ''
    ${repoConfig.workstation.username} ALL=(root) NOPASSWD: /run/current-system/sw/bin/nixos-rebuild
  '';

  # Gruvbox light variant — pick "light" from the GRUB menu, or switch live:
  # sudo /run/current-system/specialisation/light/bin/switch-to-configuration switch
  # mkForce: stylix options are plain-priority in nixos/theme.nix, so the
  # specialisation must win the definition conflict explicitly.
  specialisation.light.configuration = {
    stylix.base16Scheme = lib.mkForce ../../themes/gruvbox-light.yaml;
    stylix.polarity = lib.mkForce "light";
  };

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
