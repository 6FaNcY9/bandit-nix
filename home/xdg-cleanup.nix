{
  config,
  pkgs,
  ...
}: let
  homeAudit = pkgs.writeShellApplication {
    name = "bandit-home-audit";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.gnused];
    text = ''
      cache_root="${config.xdg.cacheHome}"

      printf 'Rebuildable caches (safe cleanup candidates)\n'
      for path in \
        "$cache_root/bun" \
        "$cache_root/fontconfig" \
        "$cache_root/mesa_shader_cache" \
        "$cache_root/nix" \
        "$cache_root/nix-index" \
        "$cache_root/npm" \
        "$cache_root/python" \
        "$cache_root/thumbnails" \
        "$cache_root/uv" \
        "$cache_root/yarn"
      do
        if [ -e "$path" ]; then
          du -sh "$path"
        fi
      done | sort -hr

      printf '\nLargest top-level home entries (review only; never auto-deleted)\n'
      {
        find "${config.home.homeDirectory}" -mindepth 1 -maxdepth 1 -exec du -sh {} + 2>/dev/null || true
      } \
        | sort -hr \
        | sed -n '1,30p'

      printf '\nRun bandit-cache-clean --confirm to remove only the listed rebuildable caches.\n'
    '';
  };

  cacheClean = pkgs.writeShellApplication {
    name = "bandit-cache-clean";
    runtimeInputs = [pkgs.coreutils pkgs.findutils];
    text = ''
      if [ "''${1:-}" != "--confirm" ]; then
        echo "Refusing cleanup without --confirm. Run bandit-home-audit first." >&2
        exit 2
      fi

      clean_contents() {
        local path="$1"
        if [ -d "$path" ]; then
          find "$path" -mindepth 1 -delete
          printf 'cleared %s\n' "$path"
        fi
      }

      for path in \
        "${config.xdg.cacheHome}/bun" \
        "${config.xdg.cacheHome}/fontconfig" \
        "${config.xdg.cacheHome}/mesa_shader_cache" \
        "${config.xdg.cacheHome}/nix" \
        "${config.xdg.cacheHome}/nix-index" \
        "${config.xdg.cacheHome}/npm" \
        "${config.xdg.cacheHome}/python" \
        "${config.xdg.cacheHome}/thumbnails" \
        "${config.xdg.cacheHome}/uv" \
        "${config.xdg.cacheHome}/yarn"
      do
        clean_contents "$path"
      done
    '';
  };
in {
  xdg.enable = true;

  home = {
    packages = [homeAudit cacheClean];

    # Default homes for installers that respect the XDG base-directory spec.
    # For new top-level dotdirs, first audit with:
    #   ~/src/bandit-nix/script/dotdir-audit
    # Then add only documented/supported relocations here.
    sessionVariables = {
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
    sessionPath = [
      "${config.home.homeDirectory}/.local/bin"
      "${config.xdg.dataHome}/cargo/bin"
      "${config.xdg.dataHome}/bun/bin"
      "${config.xdg.dataHome}/go/bin"
      "${config.xdg.dataHome}/dotnet/tools"
    ];
  };
}
