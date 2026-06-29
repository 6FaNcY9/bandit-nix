{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./xdg-cleanup.nix
    ./ssh.nix
    ./git.nix
    ./theme.nix
    ./qt.nix
    ./desktop/i3.nix
    ./desktop/netmenu.nix
    ./desktop/dunst.nix
    ./desktop/rofi.nix
    ./desktop/firefox
    ./desktop/thunderbird.nix
    ./desktop/xfce.nix
    ./desktop/panel.nix
    ./desktop/powermenu.nix
    ./editor.nix
    ./terminal
    ./node.nix
  ];

  home = {
    username = "vino";
    homeDirectory = "/home/vino";
    stateVersion = "25.11";
    packages = with pkgs; [
      bitwarden-cli
    ];
  };
}
