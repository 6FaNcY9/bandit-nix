{pkgs, ...}: {
  programs.npm = {
    enable = true;
    package = pkgs.nodejs;
    settings = {
      prefix = "$HOME/.npm-global";
    };
  };

  # Make npm-global bins (e.g. from npm install -g) available in PATH
  home.sessionPath = ["$HOME/.npm-global/bin"];
}
