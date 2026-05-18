_: {
  programs = {
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting ""
      '';
      shellAbbrs = {
        # nix
        ns = "nh os switch";
        nt = "nh os test";
        nfu = "nix flake update";
        ngc = "nix-collect-garbage -d";
        # navigation
        ll = "eza -la";
        cat = "bat";
        cd = "z";
      };
    };
    eza.enable = true;
    bat.enable = true;
    zoxide.enable = true;
    fzf.enable = true;
  };
}
