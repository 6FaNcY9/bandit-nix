# Home Manager root for the new tree.
{
  bandit,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./xdg-cleanup.nix
    ./xdg-shims.nix
    ./dotfiles.nix
    ./ssh.nix
    ./git.nix
    ./theme.nix
    ./qt.nix
    ./desktop
    ./editor
    ./terminal
    ./node.nix
  ];

  home = {
    inherit (bandit.workstation) username homeDirectory;
    stateVersion = "25.11";
    sessionVariables = {
      # Single-user host: gcr's ssh agent socket under the user runtime dir.
      SSH_AUTH_SOCK = "/run/user/1000/gcr/ssh";
    };
    packages = [
      pkgs.bitwarden-cli
      pkgs.gruvbox-plus-icons
      pkgs.chromium
    ];
  };
}
