{inputs, ...}: {
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./shell.nix
    ./ssh.nix
    ./git.nix
    ./theme.nix
    ./qt.nix
    ./desktop/i3.nix
    ./desktop/dunst.nix
    ./desktop/rofi.nix
    ./desktop/firefox.nix
    ./desktop/xfce-colors.nix
    ./desktop/panel.nix
    ./desktop/powermenu.nix
    ./editor.nix
    ./terminal.nix
    ./node.nix
  ];

  home = {
    username = "vino";
    homeDirectory = "/home/vino";
    stateVersion = "25.11";
  };
}
