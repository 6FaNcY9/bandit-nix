{
  config,
  lib,
  pkgs,
  ...
}: let
  r = config.bandit.theme.roles;
  # Same rgb(rrggbb) format as home/desktop/hyprland/settings.nix.
  rgb = color: "rgb(${lib.removePrefix "#" color})";

  # Scaffolds a security engagement workspace: a dated, private (0700) folder
  # with a scope record, a methodology note template, evidence folders and its
  # own devenv so tooling stays per-engagement rather than system-wide. This is
  # organisation only — it structures authorised white-hat work, it does not
  # carry or run any tooling itself.
  opsTemplates = pkgs.runCommandLocal "bandit-ops-templates" {} ''
    cp -r ${../../templates/ops} "$out"
  '';

  ops = pkgs.writeShellApplication {
    name = "ops";
    runtimeInputs = [pkgs.git pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.procps];
    text = ''
      opsdir="''${BANDIT_OPS_DIR:-$HOME/ops}"
      templates="${opsTemplates}"
      statedir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bandit"
      modefile="$statedir/mode"

      resolve() {
        find "$opsdir" -maxdepth 1 -mindepth 1 -type d -name "*$1*" 2>/dev/null | sort | head -1
      }

      # Refresh the indicators: waybar custom/mode (signal 8) and the Hyprland
      # active border. Both are no-ops headless / outside a Hyprland session.
      refresh() {
        pkill -RTMIN+8 -x waybar 2>/dev/null || true
        if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
          hyprctl keyword general:col.active_border "$1" >/dev/null 2>&1 || true
        fi
      }

      usage() {
        cat >&2 <<'USAGE'
      ops new <name> [-s "<scope summary>"]   create a dated engagement workspace
      ops ls                                  list engagements
      ops path <name>                         print an engagement's path (prefix match)
      ops on <name>                           enter ops mode for an engagement
      ops off                                 leave ops mode (back to dev)
      ops status                              print the active engagement, or "dev"
      USAGE
        exit 2
      }

      cmd="''${1:-}"; shift || true
      case "$cmd" in
        new)
          name=""; scope=""
          while [ "$#" -gt 0 ]; do
            case "$1" in
              -s) scope="''${2:-}"; shift 2 ;;
              -*) echo "unknown flag: $1" >&2; exit 2 ;;
              *) name="$1"; shift ;;
            esac
          done
          [ -n "$name" ] || usage
          case "$name" in
            *[!A-Za-z0-9._-]*|.|..) echo "invalid engagement name: $name" >&2; exit 2 ;;
          esac
          dest="$opsdir/$(date +%Y-%m-%d)-$name"
          [ -e "$dest" ] && { echo "already exists: $dest" >&2; exit 2; }

          ( umask 077
            mkdir -p -- "$dest"/{notes,evidence,logs,report}
            cp -- "$templates/notes.md" "$dest/notes/notes.md"
            cp -- "$templates/devenv.nix" "$dest/devenv.nix"
            cp -- "$templates/devenv.yaml" "$dest/devenv.yaml"
            {
              cat "$templates/scope.txt"
              [ -n "$scope" ] && printf '\nSummary: %s\n' "$scope"
            } > "$dest/scope.txt"
            chmod -R u+w "$dest"
            printf 'eval "$(devenv direnvrc)"\nuse devenv\n' > "$dest/.envrc"
            printf '.devenv*\n.direnv\n' > "$dest/.gitignore"
          )
          git -C "$dest" init -q
          ( cd "$dest" && direnv allow . 2>/dev/null || true )
          printf 'created %s\nFill in scope.txt before you start.\n' "$dest"
          ;;
        ls)
          [ -d "$opsdir" ] || exit 0
          for d in "$opsdir"/*/; do
            [ -d "$d" ] || continue
            printf '%s\n' "$(basename "$d")"
          done
          ;;
        path)
          name="''${1:-}"; [ -n "$name" ] || usage
          match="$(resolve "$name")"
          [ -n "$match" ] && printf '%s\n' "$match"
          ;;
        on)
          name="''${1:-}"; [ -n "$name" ] || usage
          match="$(resolve "$name")"
          [ -n "$match" ] || { echo "no engagement matches: $name" >&2; exit 1; }
          if [ ! -f "$match/scope.txt" ] || grep -q 'SCOPE-NOT-FILLED' "$match/scope.txt"; then
            echo "refusing: fill in $match/scope.txt (and remove SCOPE-NOT-FILLED) first" >&2
            exit 1
          fi
          ( umask 077
            mkdir -p -- "$statedir"
            tmp="$(mktemp "$statedir/mode.XXXXXX")"
            printf 'name=%s\npath=%s\nsince=%s\n' \
              "$(basename "$match")" "$match" "$(date -Iseconds)" > "$tmp"
            mv -f -- "$tmp" "$modefile"
          )
          refresh "${rgb r.ops}"
          printf 'ops mode: %s\n' "$(basename "$match")"
          ;;
        off)
          rm -f -- "$modefile"
          refresh "${rgb r.accent}"
          echo "dev mode"
          ;;
        status)
          if [ -f "$modefile" ]; then cat -- "$modefile"; else echo dev; fi
          ;;
        *) usage ;;
      esac
    '';
  };
in {
  home.packages = [ops];
}
