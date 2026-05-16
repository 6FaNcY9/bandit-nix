{pkgs, ...}: {
  # X server
  services.greetd = {
    enable = true;
    settings.default_session.command = ''
      ${pkgs.greetd.tuigreet}/bin/tuigreet \
      --time \
      --remember \
      --cmd "${pkgs.xorg.xinit}/bin/startx ${pkgs.xfce.xfce4-session}/bin/xfce4-session"
    '';
  };

  services.xserver = {
    enable = true;

    # XFCE provides the session/panel/daemons
    # but i3 replaces its window manager
    desktopManager.xfce = {
      enable = true;
      noDesktop = true; # no xfdesktop (wallpaper/icons daemon)
      enableXfwm = false; # disable XFCE's own WM — i3 takes over
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

  # Tell XFCE session to use i3 as WM
  environment.systemPackages = with pkgs; [
    xfce.xfce4-panel
    xfce.xfce4-settings
    xfce.xfce4-session
    xfce.thunar
    xfce.xfce4-terminal
    xfce.xfce4-power-manager
    xfce.xfce4-notifyd
  ];

  # Needed for XFCE settings daemon and GTK apps
  programs.dconf.enable = true;
}
