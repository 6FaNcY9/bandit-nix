{ ... }:
{
  programs.fish = {
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

  programs.eza.enable    = true;
  programs.bat.enable    = true;
  programs.zoxide.enable = true;
  programs.fzf.enable    = true;
}
