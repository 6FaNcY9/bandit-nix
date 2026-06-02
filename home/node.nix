{pkgs, ...}: {
  programs.npm = {
    enable = true;
    package = pkgs.nodejs;
    settings = {
      prefix = "$HOME/.npm-global";
    };
  };

  home.packages = with pkgs; [
    bun # required by claude-mem worker runtime
    unzip # required by bun installer scripts
    uv # python package runner (replaces foreign binary at ~/.local/bin/uvx)
  ];

  # Make npm-global bins (e.g. from npm install -g) available in PATH
  home.sessionPath = ["$HOME/.npm-global/bin"];
}
