{pkgs, ...}: {
  programs = {
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "*" = {
          HashKnownHosts = "yes";
          ServerAliveInterval = 60;
          ServerAliveCountMax = 3;
        };
        "github.com" = {
          Hostname = "github.com";
          User = "git";
          IdentityFile = "~/.ssh/github";
          IdentitiesOnly = true;
        };
        "6FaNcY9" = {
          Hostname = "github.com";
          User = "git";
          IdentityFile = "~/.ssh/github";
          IdentitiesOnly = true;
        };
        "BanditStudent" = {
          Hostname = "github.com";
          User = "git";
          IdentityFile = "~/.ssh/github-banditstudent";
          IdentitiesOnly = true;
        };
      };
    };

    delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
        syntax-theme = "gruvbox-dark";
      };
    };

    git = {
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
          wip = "commit -m 'wip'";
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
        user.signingkey = "4D8770567A65FE1369E2BCC1611871842A8C1619";
      };
    };
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pkgs.pinentry-gtk2;
    defaultCacheTtl = 3600;
    maxCacheTtl = 14400; # 4 h — was 24 h
  };
}
