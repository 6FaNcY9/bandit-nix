{pkgs, ...}: {
  # Retro power menu — rofi-rendered, bound to XF86PowerOff and Mod+Escape
  home.file.".local/bin/powermenu" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      chosen=$(printf '%s\n' \
        "  Lock" \
        "  Logout" \
        "  Suspend" \
        "  Reboot" \
        "  Shutdown" \
        | ${pkgs.rofi}/bin/rofi -dmenu -i -p "session" -theme retro-power -no-show-icons -lines 5)
      case "$chosen" in
        *Lock)     ${pkgs.xfce4-screensaver}/bin/xfce4-screensaver-command --lock ;;
        *Logout)   ${pkgs.i3}/bin/i3-msg exit ;;
        *Suspend)  ${pkgs.xfce4-screensaver}/bin/xfce4-screensaver-command --lock; systemctl suspend ;;
        *Reboot)   systemctl reboot ;;
        *Shutdown) systemctl poweroff ;;
      esac
    '';
  };
}
