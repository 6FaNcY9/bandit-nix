{
  pkgs,
  lib,
  ...
}: {
  # X server
  services = {
    displayManager.defaultSession = "xfce+i3";

    xserver = {
      displayManager.lightdm.enable = true;
      enable = true;

      xkb = {
        layout = "at"; # Austrian keyboard, matching the previous nixos-config repo
        variant = "";
      };

      desktopManager.xfce = {
        enable = true;
        noDesktop = true;
        enableXfwm = false;
      };

      windowManager.i3 = {
        enable = true;
        extraPackages = with pkgs; [
          i3status
          i3lock
          dmenu
        ];
      };
    };

    # Input devices
    libinput = {
      enable = true;
      touchpad = {
        tapping = true;
        naturalScrolling = true;
        disableWhileTyping = true;
        accelProfile = "adaptive";
      };
    };
    # For mounting/unmounting drives in file managers (e.g. Thunar)
    udisks2.enable = true;
    gvfs.enable = true;
  };

  # Tell XFCE session to use i3 as WM
  environment.systemPackages = with pkgs; [
    xfce4-panel
    xfce4-settings
    xfce4-session
    thunar
    xfce4-terminal
    xfce4-power-manager
    xfce4-notifyd
    brightnessctl
  ];

  # Polkit for privilege escalation in GUI apps (e.g. software updater)
  security.polkit.enable = true;

  # Needed for XFCE settings daemon and GTK apps
  programs.dconf.enable = true;
  hardware.acpilight.enable = true;

  # XDG portals for sandboxed apps (flatpak, snap, etc.)
  xdg.portal = {
    enable = true;
    wlr.enable = false;
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
    config.common.default = "gtk";
  };

  qt = {
    enable = true;
    platformTheme = lib.mkForce "gtk2";
  };
}
