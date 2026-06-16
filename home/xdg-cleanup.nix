{config, ...}: {
  xdg.enable = true;

  # Default homes for installers that respect the XDG base-directory spec.
  # For new top-level dotdirs, first audit with:
  #   ~/src/bandit-nix/script/dotdir-audit
  # Then add only documented/supported relocations here.
  home.sessionVariables = {
    XDG_CONFIG_HOME = config.xdg.configHome;
    XDG_DATA_HOME = config.xdg.dataHome;
    XDG_CACHE_HOME = config.xdg.cacheHome;
    XDG_STATE_HOME = config.xdg.stateHome;

    # Language/package installers.
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    GOPATH = "${config.xdg.dataHome}/go";
    GOMODCACHE = "${config.xdg.cacheHome}/go/pkg/mod";
    BUN_INSTALL = "${config.xdg.dataHome}/bun";
    BUN_INSTALL_CACHE_DIR = "${config.xdg.cacheHome}/bun/install/cache";
    DOTNET_CLI_HOME = "${config.xdg.dataHome}/dotnet";
    NUGET_PACKAGES = "${config.xdg.cacheHome}/NuGetPackages";
    NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
    NODE_REPL_HISTORY = "${config.xdg.stateHome}/node/repl_history";
    PYTHON_HISTORY = "${config.xdg.stateHome}/python/history";
    UV_CACHE_DIR = "${config.xdg.cacheHome}/uv";
    UV_PYTHON_DOWNLOADS = "never";
    UV_PYTHON_INSTALL_DIR = "${config.xdg.dataHome}/uv/python";
    UV_TOOL_DIR = "${config.xdg.dataHome}/uv/tools";

    # Common tool state/history/cache.
    ANDROID_USER_HOME = "${config.xdg.dataHome}/android";
    DOCKER_CONFIG = "${config.xdg.configHome}/docker";
    GRADLE_USER_HOME = "${config.xdg.dataHome}/gradle";
    IPYTHONDIR = "${config.xdg.configHome}/ipython";
    JUPYTER_CONFIG_DIR = "${config.xdg.configHome}/jupyter";
    HISTFILE = "${config.xdg.stateHome}/bash/history";
    LESSHISTFILE = "${config.xdg.stateHome}/less/history";
    PARALLEL_HOME = "${config.xdg.configHome}/parallel";
    SQLITE_HISTORY = "${config.xdg.stateHome}/sqlite/history";
    WGETRC = "${config.xdg.configHome}/wgetrc";
  };

  # Binaries from user-level installers should resolve without adding dotdirs
  # directly to the top-level home directory.
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.xdg.dataHome}/cargo/bin"
    "${config.xdg.dataHome}/bun/bin"
    "${config.xdg.dataHome}/go/bin"
    "${config.xdg.dataHome}/dotnet/tools"
  ];
}
