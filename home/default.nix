{inputs, ...}: {
  imports = [
    ./shell.nix
    ./editor.nix
    ./git.nix
    ./theme.nix
    ./desktop/i3.nix
    inputs.nixvim.homeModules.nixvim
  ];

  home.username = "vino";
  home.homeDirectory = "/home/vino";
  home.stateVersion = "25.11";
}
