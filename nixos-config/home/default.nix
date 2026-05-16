{ ... }:
{
  imports = [
    ./shell.nix
    ./editor.nix
    ./git.nix
    ./theme.nix
    ./desktop/i3.nix
    ./desktop/picom.nix
    ./desktop/xfce-panel.nix
  ];

  home.username = "vino";
  home.homeDirectory = "/home/vino";
  home.stateVersion = "24.11";
}
