{inputs, ...}: {
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./shell.nix
    ./git.nix
    ./theme.nix
    ./desktop/i3.nix
    ./desktop/dunst.nix
    ./desktop/rofi.nix
    ./desktop/firefox.nix
    ./desktop/xfce-colors.nix
    ./desktop/panel.nix
    ./editor.nix
    ./terminal.nix
  ];

  home = {
    username = "vino";
    homeDirectory = "/home/vino";
    stateVersion = "25.11";
  };
}
