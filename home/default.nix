{
  inputs,
  pkgs,
  repoConfig,
  ...
}: {
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./xdg-cleanup.nix
    ./ssh.nix
    ./git.nix
    ./theme.nix
    ./qt.nix
    ./desktop/hyprland.nix
    ./desktop/files.nix
    ./desktop/netmenu.nix
    ./desktop/mako.nix
    ./desktop/rofi-wayland.nix
    ./desktop/firefox
    ./desktop/thunderbird.nix
    ./desktop/waybar.nix
    ./desktop/powermenu.nix
    ./editor.nix
    ./terminal
    ./node.nix
  ];

  home = {
    inherit (repoConfig.workstation) username homeDirectory;
    stateVersion = "25.11";
    packages = with pkgs; [
      bitwarden-cli
      gruvbox-plus-icons
    ];
  };
}
