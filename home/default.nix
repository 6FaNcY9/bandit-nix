{inputs, ...}: {
  imports = [
    inputs.nixvim.homeModules.nixvim
    inputs.stylix.homeModules.stylix
    ./shell.nix
    ./git.nix
    ./theme.nix
    ./desktop/i3.nix
    ./desktop/firefox.nix
    ./desktop/xfce-colors.nix
    ./editor.nix
    ./terminal.nix
  ];

  home = {
    username = "vino";
    homeDirectory = "/home/vino";
    stateVersion = "25.11";
  };
}
