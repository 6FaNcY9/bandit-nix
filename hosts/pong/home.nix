# Home Manager for the phone "pong" (Nothing Phone (2)), run inside the root
# chroot from hosts/pong/bootstrap. HOME is /home/vino inside the chroot; shared
# state lives in the Termux home and is linked in, so Home Manager never writes
# /nix/store links into the Termux home (the Termux rescue kit reads it).
{
  config,
  lib,
  pkgs,
  inputs,
  bandit,
  ...
}: let
  termux = bandit.phone.termuxHome;
  link = name: config.lib.file.mkOutOfStoreSymlink "${termux}/${name}";
  # Termux:API commands, answered through the bridge (hosts/pong/api/pong-api).
  apiCommands = lib.splitString "\n" (lib.fileContents ./api/commands.txt);
  termuxApi = pkgs.runCommandLocal "pong-termux-api" {} ''
    mkdir -p $out/bin
    install -m 755 ${./api/pong-api} $out/bin/pong-api
    for c in ${lib.escapeShellArgs apiCommands}; do ln -s pong-api "$out/bin/$c"; done
  '';
in {
  imports = [
    inputs.nixvim.homeModules.nixvim
    inputs.nix-index-database.homeModules.nix-index
    ../../modules/user/ssh.nix
    ../../modules/user/git.nix
    ../../modules/user/editor
    ../../modules/user/terminal
    ../../modules/user/node.nix
  ];

  # Colours only (zsh and nixvim read them); no desktop targets on the phone.
  stylix.autoEnable = false;

  programs.home-manager.enable = true;

  home = {
    inherit (bandit.phone) username homeDirectory;
    stateVersion = "25.11";
    # The chroot has only busybox sh; the basic userland comes from here.
    packages =
      [termuxApi]
      ++ (with pkgs; [
        bitwarden-cli
        coreutils
        diffutils
        findutils
        gawk
        gnugrep
        gnused
        gnutar
        gzip
        xz
        less
        which
        procps
        curl
        openssh
      ]);
    file = lib.genAttrs ["projects" "src" "storage" "backups" ".claude" ".claude.json"] (n: {source = link n;});
  };
}
