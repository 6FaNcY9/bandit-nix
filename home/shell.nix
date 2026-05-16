_: {
  programs = {
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting ""
      '';
      shellAbbrs = {
        # nix
        ns  = "nixos-rebuild switch --flake .#bandit";
        nt  = "nixos-rebuild test --flake .#bandit";
        nfu = "nix flake update";
        ngc = "nix-collect-garbage -d";
        # navigation
        ll  = "eza -la";
        cat = "bat";
        cd  = "z";
      };
    };
    eza.enable    = true;
    bat.enable    = true;
    zoxide.enable = true;
    fzf.enable    = true;
  };
}