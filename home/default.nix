{ ... }:
{
  imports = [
    ./shell.nix
    ./editor.nix
    ./git.nix
    ./desktop/i3.nix
    ./desktop/xfce-panel.nix
  ];

  home.username = "vino";
  home.homeDirectory = "/home/vino";
  home.stateVersion = "25.11";
}
