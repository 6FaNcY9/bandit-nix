{
  inputs,
  pkgs,
  repoConfig,
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
    inherit (repoConfig.workstation) username homeDirectory;
    stateVersion = "25.11";
    sessionVariables = {
      # Single-user host: gcr's ssh agent socket under the user runtime dir.
      SSH_AUTH_SOCK = "/run/user/1000/gcr/ssh";
    };
    packages = with pkgs; [
      bitwarden-cli
      gruvbox-plus-icons
      chromium
    ];
  };
}
