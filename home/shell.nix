_: {
  programs = {
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting ""
        if test -r /run/secrets/cachix-secret
          set -gx CACHIX_AUTH_TOKEN (cat /run/secrets/cachix-secret)
        end
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
