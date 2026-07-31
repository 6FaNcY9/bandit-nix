{config, ...}: let
  shim = target: name: {
    name = ".${name}";
    value.source = config.lib.file.mkOutOfStoreSymlink target;
  };
  dataShims = [
    "aider"
    "aider-desk"
    "gemini"
    "augment"
    "bob"
    "codebuddy"
    "codeium"
    "codemaker"
    "codestudio"
    "commandcode"
    "continue"
    "factory"
    "forge"
    "hermes"
    "copilot"
    "astrbot"
    "autohand"
    "codeartsdoer"
    "claude-mem"
    "firecrawl"
    "crawl"
    "cvdr"
    "atuin"
    "PwnChromiumData"
    "package-manager"
    "wpscan"
    "nuclei-templates"
  ];
  configShims = ["vscode" "BurpSuite" "msf4" "java"];
  cacheShims = ["compose-cache"];
in {
  # Declarative compatibility shims: stubborn apps hardcode ~/.<tool>; the real
  # directories live in XDG homes. Rebuilds recreate this structure, so
  # top-level dotfile creep cannot silently return.
  home.file = builtins.listToAttrs (
    map (n: shim "${config.xdg.dataHome}/${n}" n) dataShims
    ++ map (n: shim "${config.xdg.configHome}/${n}" n) configShims
    ++ map (n: shim "${config.xdg.cacheHome}/${n}" n) cacheShims
  );
}
