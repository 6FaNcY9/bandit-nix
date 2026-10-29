{lib, ...}: {
  imports = [
    ./hardware.nix
  ];

  networking.hostName = "bandit";
  system.stateVersion = "25.11";

  # No NOPASSWD sudo rule for nixos-rebuild: it would give any process running
  # as the user passwordless root via `--flake /tmp/x`. Rebuild with `nh`
  # (aliases ns/nt), which asks for the sudo password or fingerprint.

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

  # Framework 13 AMD hardware support.
  services = {
    fprintd.enable = true;
    # upower provides battery status used by status bars and desktop apps.
    upower.enable = true;
    # Laptop tailnet access: reach bandit-lab (100.125.161.81) from any
    # network without the Cloudflare Access browser flow. The lab enables its
    # own tailscaled in hosts/bandit-lab/services/webhost/default.nix.
    tailscale.enable = true;
    # iOS device pairing over USB (SideStore/iloader sideloading).
    usbmuxd.enable = true;
    # Broken space key: tap AltGr for space, hold it (>200ms, not mid-typing)
    # to keep AltGr symbols (@ { } [ ] \ |) on the Austrian layout.
    # Built-in keyboard only (0001:0001, AT Translated Set 2): its water-damaged
    # space key is ignored; an external keyboard keeps its own space key.
    keyd = {
      enable = true;
      keyboards.internal = {
        ids = ["0001:0001"];
        settings.main = {
          rightalt = "overloadi(space, overloadt2(altgr, space, 200), 150)";
          space = "noop";
        };
      };
    };
  };

  # Random MAC per network, stable per SSID: defeats cross-network
  # tracking without breaking captive portals or per-network DHCP leases.
  networking.networkmanager.wifi.macAddress = "stable";
  # AMD CPU microcode updates — applied at boot for security and stability.
  # Redistributable firmware blobs for WiFi (ath11k) and Bluetooth.
  hardware = {
    cpu.amd.updateMicrocode = true;
    enableRedistributableFirmware = true;
  };

  # ── Programs ───────────────────────────────────────────────
  programs = {
    nix-ld.enable = true;
  };
}
