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

  home.packages = [
    pkgs.bun # required by claude-mem worker runtime
    pkgs.unzip # required by bun installer scripts
    pkgs.pnpm
    pkgs.biome
  ];

  # Make npm-global bins (e.g. from npm install -g) available in PATH
  home.sessionPath = ["${config.xdg.dataHome}/npm-global/bin"];
}
