{
  config,
  pkgs,
  ...
}: {
  programs.npm = {
    enable = true;
    package = pkgs.nodejs;
    settings = {
      prefix = "${config.xdg.dataHome}/npm-global";
      cache = "${config.xdg.cacheHome}/npm";
    };
  };

  home.packages = with pkgs; [
    bun # required by claude-mem worker runtime
    unzip # required by bun installer scripts
    uv # python package runner (replaces foreign binary at ~/.local/bin/uvx)
  ];

  # Make npm-global bins (e.g. from npm install -g) available in PATH
  home.sessionPath = ["${config.xdg.dataHome}/npm-global/bin"];
}
