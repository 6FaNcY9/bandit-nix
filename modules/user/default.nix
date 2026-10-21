# Home Manager root for the new tree. legacyHome lists the old home/ modules
# not yet ported; it shrinks per phase-2 task and disappears at the end.
{
  bandit,
  inputs,
  pkgs,
  ...
}: let
  legacyHome = [
    ../../home/xdg-cleanup.nix
    ../../home/xdg-shims.nix
    ../../home/dotfiles.nix
    ../../home/ssh.nix
    ../../home/git.nix
    ../../home/theme.nix
    ../../home/qt.nix
    ../../home/desktop
    ../../home/editor
    ../../home/terminal
    ../../home/node.nix
  ];
in {
  imports = [inputs.nixvim.homeModules.nixvim] ++ legacyHome;

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
