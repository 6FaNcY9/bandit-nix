{
  config,
  pkgs,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;

  # Super+Space command palette. Its menus (lage, waybar-target, keybinds-menu, net-menu,
  # powermenu, hypr-cockpit, hypr-screenshot) are reached through ~/.local/bin, not runtimeInputs.
  palette = pkgs.writeShellApplication {
    name = "palette";
    runtimeInputs = [config.programs.rofi.package pkgs.jq pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.mako pkgs.kitty pkgs.cliphist pkgs.wl-clipboard pkgs.libnotify];
    text = "PAL_DIM='${colors.base03}' PAL_WARN='${colors.base0A}'\n" + builtins.readFile ../../../tools/palette.sh;
  };
in {
  home.file.".local/bin/palette".source = "${palette}/bin/palette";
}
