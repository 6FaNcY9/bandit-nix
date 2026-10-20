{
  config,
  lib,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  projDir = "${home}/proj";

  # devenv project templates live in the Nix store (templates/devenv/<lang>).
  templates = pkgs.runCommandLocal "bandit-devenv-templates" {} ''
    cp -r ${../../templates/devenv} "$out"
  '';

  proj = pkgs.writeShellApplication {
    name = "proj";
    runtimeInputs = [pkgs.git pkgs.coreutils pkgs.gnugrep pkgs.findutils];
    text = ''
      projdir="''${XDG_PROJECTS_DIR:-$HOME/proj}"
      templates="${templates}"

      usage() {
        cat >&2 <<'USAGE'
      proj new <name> [-t rust|node|python|go|nix|c|empty]   create a devenv project
      proj ls                                                list projects
      proj path <name>                                       print a project's path
      USAGE
        exit 2
      }

      cmd="''${1:-}"; shift || true
      case "$cmd" in
        new)
          name=""; tmpl="empty"
          while [ "$#" -gt 0 ]; do
            case "$1" in
              -t) tmpl="''${2:-}"; shift 2 ;;
              -*) echo "unknown flag: $1" >&2; exit 2 ;;
              *) name="$1"; shift ;;
            esac
          done
          [ -n "$name" ] || usage
          case "$name" in
            *[!A-Za-z0-9._-]*|.|..) echo "invalid project name: $name" >&2; exit 2 ;;
          esac
          [ -d "$templates/$tmpl" ] || { echo "unknown template: $tmpl" >&2; exit 2; }
          dest="$projdir/$name"
          [ -e "$dest" ] && { echo "already exists: $dest" >&2; exit 2; }

          mkdir -p -- "$dest"
          cp -- "$templates/$tmpl/devenv.nix" "$dest/devenv.nix"
          cp -- "$templates/$tmpl/devenv.yaml" "$dest/devenv.yaml"
          chmod u+w "$dest/devenv.nix" "$dest/devenv.yaml"
          printf 'eval "$(devenv direnvrc)"\nuse devenv\n' > "$dest/.envrc"
          printf '.devenv*\n.direnv\ndevenv.local.nix\n' > "$dest/.gitignore"
          git -C "$dest" init -q
          ( cd "$dest" && direnv allow . 2>/dev/null || true )
          printf 'created %s (%s). cd in to load the devenv shell.\n' "$dest" "$tmpl"
          ;;
        ls)
          [ -d "$projdir" ] || exit 0
          for d in "$projdir"/*/; do
            [ -d "$d" ] || continue
            langs=""
            if [ -f "$d/devenv.nix" ]; then
              langs="$(grep -oE 'languages\.[a-z]+\.enable' "$d/devenv.nix" | cut -d. -f2 | paste -sd, - || true)"
            fi
            printf '%-24s %s\n' "$(basename "$d")" "$langs"
          done
          ;;
        path)
          name="''${1:-}"; [ -n "$name" ] || usage
          printf '%s\n' "$projdir/$name"
          ;;
        *) usage ;;
      esac
    '';
  };
in {
  home.packages = [proj];

  # `p <name>` cds into a project (tab-completes project names); `p` alone -> ~/proj.
  programs.zsh.initContent = lib.mkAfter ''
    p() {
      local root="''${XDG_PROJECTS_DIR:-$HOME/proj}"
      if [ -z "$1" ]; then cd "$root"; else cd "$root/$1"; fi
    }
    _p() { _path_files -W "''${XDG_PROJECTS_DIR:-$HOME/proj}" -/ }
    compdef _p p
  '';
}
