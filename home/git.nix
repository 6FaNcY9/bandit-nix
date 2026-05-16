{pkgs, ...}: {
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
      syntax-theme = "gruvbox-dark";
    };
  };

  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "6FaNcY9";
        email = "29282675+6FaNcY9@users.noreply.github.com";
      };

      alias = {
        st = "status -sb";
        lg = "log --oneline --graph --decorate";
        undo = "reset --soft HEAD~1";
        wip = "commit -am 'wip'";
      };

      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      merge.conflictstyle = "diff3";
      rerere.enabled = true;

      core = {
        autocrlf = "input";
        editor = "nvim";
      };

      commit.gpgsign = true;
      user.signingkey = "B872E229ADE55151";
    };
  };

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-gtk2;
    defaultCacheTtl = 3600;
    maxCacheTtl = 86400;
  };
}
