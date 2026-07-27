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
        *Lock)     ${pkgs.hyprlock}/bin/hyprlock ;;
        *Logout)   ${pkgs.hyprland}/bin/hyprctl dispatch exit ;;
        *Suspend)  ${pkgs.hyprlock}/bin/hyprlock & systemctl suspend ;;
        *Reboot)   systemctl reboot ;;
        *Shutdown) systemctl poweroff ;;
      esac
    '';
  };
}
