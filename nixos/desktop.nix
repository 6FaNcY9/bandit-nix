{ ... }:
{
  services.xserver.enable = true;
  services.xserver.windowManager.i3.enable = true;
  services.picom.enable = true;

  services.greetd.enable = true;
  services.greetd.settings.default_session.command = "tuigreet --cmd i3";
}
