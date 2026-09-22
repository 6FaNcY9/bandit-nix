{
  pkgs,
  lib,
  homePackages,
}: let
  packageByName = name:
    lib.findFirst
    (package: (package.name or "") == name)
    (throw "missing Home Manager package: ${name}")
    homePackages;
  dotdirAudit = packageByName "bandit-dotdir-audit";
  dotdirAdopt = packageByName "bandit-dotdir-adopt";
in
  pkgs.runCommand "bandit-nix-dotdir-tools-check" {} ''
    export HOME="$PWD/home"
    export XDG_DATA_HOME="$PWD/data"
    export XDG_CONFIG_HOME="$PWD/config"
    export XDG_CACHE_HOME="$PWD/cache"
    mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

    if ${dotdirAdopt}/bin/bandit-dotdir-adopt >/dev/null 2>&1; then
      echo "adopt accepted missing arguments" >&2
      exit 1
    fi
    if ${dotdirAdopt}/bin/bandit-dotdir-adopt safe data extra >/dev/null 2>&1; then
      echo "adopt accepted too many arguments" >&2
      exit 1
    fi

    mkdir -p "$HOME/.nested/tool" "$XDG_DATA_HOME/nested"
    printf source > "$HOME/.nested/tool/value"
    if ${dotdirAdopt}/bin/bandit-dotdir-adopt nested/tool >/dev/null 2>&1; then
      echo "adopt accepted a name containing a path separator" >&2
      exit 1
    fi
    test -f "$HOME/.nested/tool/value"

    mkdir "$HOME/.blocked" "$XDG_DATA_HOME/blocked-target"
    printf source > "$HOME/.blocked/value"
    ln -s "$XDG_DATA_HOME/blocked-target" "$XDG_DATA_HOME/blocked"
    if ${dotdirAdopt}/bin/bandit-dotdir-adopt blocked >/dev/null 2>&1; then
      echo "adopt accepted a non-directory destination" >&2
      exit 1
    fi
    test "$(cat "$HOME/.blocked/value")" = source
    test -L "$XDG_DATA_HOME/blocked"
    test ! -e "$XDG_DATA_HOME/blocked-target/value"
    mv "$HOME/.nested" "$PWD/nested-leftovers"
    mv "$HOME/.blocked" "$PWD/blocked-leftovers"

    mkdir "$HOME/.fresh"
    printf moved > "$HOME/.fresh/value"
    ${dotdirAdopt}/bin/bandit-dotdir-adopt fresh >/dev/null
    test ! -e "$HOME/.fresh"
    test "$(cat "$XDG_DATA_HOME/fresh/value")" = moved

    mkdir "$HOME/.merge" "$XDG_DATA_HOME/merge"
    printf source > "$HOME/.merge/source-only"
    printf source-conflict > "$HOME/.merge/conflict"
    printf target-conflict > "$XDG_DATA_HOME/merge/conflict"
    ln -s missing "$HOME/.merge/source-dangling"
    ln -s missing "$HOME/.merge/target-dangling"
    ln -s missing "$XDG_DATA_HOME/merge/target-dangling"
    if ${dotdirAdopt}/bin/bandit-dotdir-adopt merge >/dev/null 2>&1; then
      echo "adopt did not report merge conflicts" >&2
      exit 1
    fi
    test "$(cat "$XDG_DATA_HOME/merge/source-only")" = source
    test "$(cat "$XDG_DATA_HOME/merge/conflict")" = target-conflict
    test "$(cat "$HOME/.merge/conflict")" = source-conflict
    test -L "$XDG_DATA_HOME/merge/source-dangling"
    test -L "$XDG_DATA_HOME/merge/target-dangling"
    test -L "$HOME/.merge/target-dangling"
    mv "$HOME/.merge" "$PWD/merge-leftovers"

    mkdir "$HOME/.unknown"
    if ${dotdirAudit}/bin/bandit-dotdir-audit >/dev/null 2>&1; then
      echo "audit missed an unshimmed dotdir" >&2
      exit 1
    fi
    rmdir "$HOME/.unknown"
    mkdir "$HOME/.cache"
    ln -s "$XDG_DATA_HOME/fresh" "$HOME/.shim"
    ${dotdirAudit}/bin/bandit-dotdir-audit >/dev/null

    touch "$out"
  ''
