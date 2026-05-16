{pkgs, ...}: {
  programs.git = {
    enable = true;
    userName = "6FaNcY9";
    userEmail = "29282675+6FaNcY9@users.noreply.github.com";

    signing = {
      key = "B872E229ADE55151";
      signByDefault = true;
    };

    delta = {
      enable = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
        syntax-theme = "gruvbox-dark";
      };
    };

    aliases = {
      st = "status -sb";
      lg = "log --oneline --graph --decorate";
      undo = "reset --soft HEAD~1";
      wip = "commit -am 'wip'";
    };

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      merge.conflictstyle = "diff3";
      core = {
        autocrlf = "input";
        editor = "nvim";
      };
      rerere.enabled = true;
    };
  };

  # gpg-agent — handles passphrase prompts for commit signing
  services.gpg-agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-gtk2; # GTK prompt fits your XFCE stack
    defaultCacheTtl = 3600; # remember passphrase for 1 hour
    maxCacheTtl = 86400; # maximum 24 hours
  };
}
