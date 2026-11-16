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
    inputs.sops-nix.homeManagerModules.sops
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

  # Keys from secrets/pong.yaml (user + pong recipients). The age key is
  # ~/.config/sops/age/keys.txt in the chroot; its copy lives in Bitwarden.
  sops = {
    defaultSopsFile = ../../secrets/pong.yaml;
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    # No XDG_RUNTIME_DIR in the chroot.
    defaultSecretsMountPoint = "${config.home.homeDirectory}/.local/share/sops-nix/secrets.d";
    defaultSymlinkPath = "${config.home.homeDirectory}/.local/share/sops-nix/secrets";
    secrets = {
      "ssh/id_pc".path = "${config.home.homeDirectory}/.ssh/id_pc";
      "ssh/id_sign".path = "${config.home.homeDirectory}/.ssh/id_sign";
      "gh/token" = {};
    };
  };
  # sops-nix only decrypts through a systemd user unit, and the chroot has no
  # systemd: run the same script on every activation.
  home.activation.pongSops = let
    svc = config.systemd.user.services.sops-nix.Service;
  in
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      run env ${lib.concatStringsSep " " (lib.toList svc.Environment)} ${lib.concatMapStringsSep " " toString (lib.toList svc.ExecStart)}
    '';

  # Host keys the owner already accepted in Termux count here too.
  programs.ssh.settings."*".UserKnownHostsFile = "~/.ssh/known_hosts ${termux}/.ssh/known_hosts";
  programs.ssh.settings.pc = {
    Hostname = bandit.lab.workstationTailscaleIp;
    User = bandit.workstation.username;
    Port = 2222;
    IdentityFile = "~/.ssh/id_pc";
    IdentitiesOnly = true;
  };

  # Like Termux today: its own GPG key, no signing by default (the laptop's
  # key is not on the phone).
  programs.git.settings = {
    commit.gpgsign = lib.mkForce false;
    user.signingkey = lib.mkForce "EED481B02CA38F6764056E3A2638AEF73F1A5A45";
  };

  programs.zsh.initContent = ''
    [[ -r ${config.sops.secrets."gh/token".path} ]] && export GH_TOKEN="$(< ${config.sops.secrets."gh/token".path})"
  '';

  home = {
    inherit (bandit.phone) username homeDirectory;
    stateVersion = "25.11";
    # The chroot has only busybox sh; the basic userland comes from here.
    packages =
      [termuxApi]
      ++ (with pkgs; [
        bashInteractive
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
