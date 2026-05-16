{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.xserver.windowManager.i3.enable = true;
  services.picom.enable = true;

  services.greetd.enable = true;
  services.greetd.settings.default_session.command =
    "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd '${pkgs.xorg.xinit}/bin/startx ${pkgs.i3}/bin/i3'";
}
