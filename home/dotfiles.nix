{pkgs, ...}: let
  # Top-level dotdirs that are allowed to stay real directories (never shims).
  allowlist = [
    ".ssh"
    ".gnupg"
    ".pki"
    ".mozilla"
    ".thunderbird"
    ".cache"
    ".config"
    ".local"
    ".nix-defexpr"
    ".icons"
    ".themes"
    ".github"
    ".home-cleanup"
  ];

  dotdirAudit = pkgs.writeShellApplication {
    name = "bandit-dotdir-audit";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      allowlist=" ${builtins.concatStringsSep " " allowlist} "
      drift=0
      for entry in "$HOME"/.[!.]*; do
        [ -d "$entry" ] || continue
        [ -L "$entry" ] && continue
        name="$(basename "$entry")"
        case "$allowlist" in
          *" $name "*) continue ;;
        esac
        printf 'unshimmed dotdir: %s\n' "$name"
        drift=1
      done
      if [ "$drift" -eq 0 ]; then
        echo "no unshimmed top-level dotdirs"
      else
        echo "run: bandit-dotdir-adopt <name> [config|cache], then add the printed line to home/xdg-shims.nix and rebuild" >&2
        exit 1
      fi
    '';
  };

  dotdirAdopt = pkgs.writeShellApplication {
    name = "bandit-dotdir-adopt";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "usage: bandit-dotdir-adopt <name> [config|cache]" >&2
        exit 2
      fi
      name="$1"
      case "$name" in
        .|..|*/*|*[!A-Za-z0-9._+-]*)
          echo "invalid dotdir name: $name" >&2
          exit 2
          ;;
      esac
      kind="''${2:-data}"
      case "$kind" in
        data) root="''${XDG_DATA_HOME:-$HOME/.local/share}" ;;
        config) root="''${XDG_CONFIG_HOME:-$HOME/.config}" ;;
        cache) root="''${XDG_CACHE_HOME:-$HOME/.cache}" ;;
        *) echo "unknown kind: $kind" >&2; exit 2 ;;
      esac

      src="$HOME/.$name"
      dst="$root/$name"
      if [ -L "$src" ]; then
        echo "$src is already a symlink (shim active): $(readlink "$src")" >&2
        exit 0
      fi
      if [ ! -d "$src" ]; then
        echo "$src is not a real directory; nothing to adopt" >&2
        exit 2
      fi

      if [ -L "$dst" ] || { [ -e "$dst" ] && [ ! -d "$dst" ]; }; then
        echo "$dst exists but is not a real directory; refusing to modify it" >&2
        exit 2
      fi

      mkdir -p -- "$root"
      conflicts=0
      if [ -d "$dst" ]; then
        # Merge: existing target files win; move only non-conflicting entries.
        for child in "$src"/.[!.]* "$src"/*; do
          [ -e "$child" ] || [ -L "$child" ] || continue
          base="$(basename "$child")"
          if [ -e "$dst/$base" ] || [ -L "$dst/$base" ]; then
            printf 'conflict, kept target: %s\n' "$dst/$base"
            conflicts=1
          else
            mv -- "$child" "$dst/$base"
            printf 'moved %s -> %s\n' "$child" "$dst/$base"
          fi
        done
        rmdir -- "$src" 2>/dev/null || echo "leftover conflicts in $src; review manually" >&2
      else
        mv -- "$src" "$dst"
        printf 'moved %s -> %s\n' "$src" "$dst"
      fi

      case "$kind" in
        data) list=dataShims ;;
        config) list=configShims ;;
        cache) list=cacheShims ;;
      esac
      printf '\nadd to %s in home/xdg-shims.nix:\n  "%s"\nthen: sudo nixos-rebuild switch --flake .#bandit\n' "$list" "$name"
      [ "$conflicts" -eq 0 ]
    '';
  };
in {
  home.packages = [dotdirAudit dotdirAdopt];
}
