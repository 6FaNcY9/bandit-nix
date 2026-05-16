{ ... }:
{
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "UTC";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  fonts.fontconfig.enable = true;
}
