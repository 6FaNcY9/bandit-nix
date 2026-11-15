# A desktop for the owner's phone: XFCE on a virtual screen (TigerVNC), localhost only.
# The phone's VNC app (AVNC) reaches it through its own SSH tunnel; the physical screen stays a
# text console. The VNC password file is made once by hand (vncpasswd -f) and never enters the
# repo; without it the unit does not start. The password guards against local services, since
# anything on the host can reach 127.0.0.1 (the guest containers cannot: own network).
{
  config,
  pkgs,
  repoConfig,
  ...
}: let
  user = repoConfig.workstation.username;
  passwd = "${config.users.users.${user}.home}/.config/tigervnc/passwd";
  start = pkgs.writeShellScript "lab-desktop" ''
    set -eu
    ${pkgs.tigervnc}/bin/Xvnc :1 -localhost -rfbport 5901 -SecurityTypes VncAuth \
      -PasswordFile ${passwd} -geometry 1920x1080 -depth 24 -AlwaysShared &
    trap 'kill $!' EXIT
    for _ in $(seq 50); do [ -S /tmp/.X11-unix/X1 ] && break; sleep 0.1; done
    # A login shell, so the session gets the system PATH and XDG directories.
    DISPLAY=:1 ${pkgs.bashInteractive}/bin/bash -lc 'exec dbus-run-session startxfce4'
  '';
in {
  # The desktop's packages and services only: no X server or display manager on the real screen.
  services.xserver.desktopManager.xfce = {
    enable = true;
    # A lock screen would ask for a login password the VNC session never needs.
    enableScreensaver = false;
  };
  environment.systemPackages = [pkgs.firefox pkgs.tigervnc];

  # Its own logind session (XDG_RUNTIME_DIR, user bus), as a display manager would give it.
  security.pam.services.lab-desktop.startSession = true;

  systemd.services.lab-desktop = {
    description = "XFCE desktop for the phone (VNC on 127.0.0.1:5901)";
    wantedBy = ["multi-user.target"];
    unitConfig.ConditionPathExists = passwd;
    serviceConfig = {
      User = user;
      PAMName = "lab-desktop";
      # A fresh /tmp on each start, so a crash never leaves a stale X lock behind.
      PrivateTmp = true;
      ExecStart = start;
      # Also after logging out in XFCE: the desktop is back five seconds later.
      Restart = "always";
      RestartSec = 5;
    };
  };
}
