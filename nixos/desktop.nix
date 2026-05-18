{pkgs, ...}: {
  # X server
  services = {
    greetd = {
      enable = true;
      settings.default_session.command = ''
        ${pkgs.tuigreet}/bin/tuigreet \
        --time \
        --remember \
        --cmd "${pkgs.xinit}/bin/startx ${pkgs.xfce4-session}/bin/xfce4-session"
      '';
    };

    xserver = {
      enable = true;

      # XFCE provides the session/panel/daemons
      # but i3 replaces its window manager
      desktopManager.xfce = {
        enable = true;
        noDesktop = true; # no xfdesktop (wallpaper/icons daemon)
        enableXfwm = false; # disable XFCE's own WM — i3 takes over
      };

      # i3 window manager with some extra tools
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

    # Polkit for privilege escalation in GUI apps (e.g. software updater)
    polkit.enable = true;
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
}
