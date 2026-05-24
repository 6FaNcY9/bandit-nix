{inputs, ...}: {
  imports = [
    inputs.nixvim.homeModules.nixvim
    inputs.stylix.homeModules.stylix
    ./shell.nix
    ./git.nix
    ./theme.nix
    ./desktop/i3.nix
    ./editor.nix
  ];

  home = {
    username = "vino";
    homeDirectory = "/home/vino";
    stateVersion = "25.11";
  };
}
