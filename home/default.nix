{...}: {
  imports = [
    ./shell.nix
    ./git.nix
    ./theme.nix
    ./desktop/i3.nix
  ];

  home = {
    username = "vino";
    homeDirectory = "/home/vino";
    stateVersion = "25.11";
  };
}
