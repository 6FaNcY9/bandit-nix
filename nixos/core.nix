{ ... }:
{
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Vienna";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  fonts.fontconfig.enable = true;
}
