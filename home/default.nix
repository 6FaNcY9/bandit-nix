{inputs, ...}: {
  imports = [
    ./shell.nix
    ./editor.nix
    ./git.nix
    ./theme.nix
    ./desktop/i3.nix
    inputs.nixvim.homeModules.nixvim
  ];

  home = {
    username = "vino";
    homeDirectory = "/home/vino";
    stateVersion = "25.11";
  };
}
