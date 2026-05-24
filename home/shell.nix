_: {
  programs = {
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting ""
      '';
      functions.cachix = ''
        # Token scoped locally so it never leaks into the global environment
        if test -r /run/secrets/cachix-secret
          set -lx CACHIX_AUTH_TOKEN (cat /run/secrets/cachix-secret)
        end
        command cachix $argv
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
