{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;

  # The self-structuring home: every kind of file has one defined place, so the
  # top level stays short and nothing scatters stray files or .dotdirs around.
  #   ~/proj   code projects (each its own devenv, see `proj`)
  #   ~/ops    security engagements (0700, see `ops`)
  #   ~/docs   documents and vaults
  #   ~/dl     downloads (auto-pruned after 14 days)
  #   ~/media  pictures / screenshots / music / videos
  #   ~/tmp    scratch, emptied on login
  dirs = [
    "proj"
    "docs"
    "media/pictures"
    "media/screenshots"
    "media/music"
    "media/videos"
    "tmp"
  ];

  migrate = pkgs.writeShellApplication {
    name = "bandit-home-migrate";
    runtimeInputs = [pkgs.coreutils pkgs.findutils];
    text = ''
      if [ "$(id -u)" -eq 0 ]; then
        echo "refusing to run as root" >&2
        exit 2
      fi
      apply=0
      [ "''${1:-}" = "--apply" ] && apply=1
      [ "$apply" -eq 0 ] && echo "DRY RUN (pass --apply to perform). Planned moves:" >&2

      move_into() {
        # move_into <old> <new>: merge old's contents into new, keep target on
        # conflict, then replace the emptied old dir with a compat symlink.
        local old="$HOME/$1" new="$HOME/$2"
        [ -e "$old" ] || return 0
        [ -L "$old" ] && return 0
        [ -d "$old" ] || return 0
        if [ "$apply" -eq 0 ]; then
          printf '  %s -> %s\n' "$old" "$new" >&2
          return 0
        fi
        mkdir -p -- "$new"
        local child base
        for child in "$old"/.[!.]* "$old"/*; do
          [ -e "$child" ] || [ -L "$child" ] || continue
          base="$(basename "$child")"
          if [ -e "$new/$base" ] || [ -L "$new/$base" ]; then
            printf 'conflict, kept target: %s\n' "$new/$base" >&2
          else
            mv -- "$child" "$new/$base"
          fi
        done
        if rmdir -- "$old" 2>/dev/null; then
          ln -s -- "$new" "$old"
          printf 'migrated %s -> %s (compat symlink left)\n' "$old" "$new"
        else
          printf 'leftover conflicts in %s; left in place\n' "$old" >&2
        fi
      }

      move_into Projects proj
      move_into src proj
      move_into Documents docs
      move_into Pictures/Screenshots media/screenshots
      move_into Pictures media/pictures
      move_into Music media/music
      move_into Videos media/videos
      move_into Downloads dl
    '';
  };
in {
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    download = "${home}/dl";
    projects = "${home}/proj";
    documents = "${home}/docs";
    pictures = "${home}/media/pictures";
    music = "${home}/media/music";
    videos = "${home}/media/videos";
    # Unused on a terminal-first setup: keep them off the top level.
    desktop = null;
    templates = null;
    publicShare = null;
  };

  home = {
    packages = [migrate];
    sessionVariables = {
      BANDIT_OPS_DIR = "${home}/ops";
    };
  };

  systemd.user = {
    # Canonical directories, created declaratively so they always exist.
    tmpfiles.rules =
      map (d: "d ${home}/${d} 0755 - - -") dirs
      ++ [
        "d ${home}/ops 0700 - - -"
        "d ${home}/dl 0755 - - -"
      ];

    services = {
      # Empty ~/tmp on each login so scratch files never accumulate.
      bandit-tmp-clean = {
        Unit.Description = "Empty ~/tmp scratch directory";
        Install.WantedBy = ["default.target"];
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.findutils}/bin/find ${home}/tmp -mindepth 1 -delete";
        };
      };
      # Prune ~/dl entries older than 14 days, daily. Never follows symlinks.
      bandit-dl-prune = {
        Unit.Description = "Prune ~/dl entries older than 14 days";
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.findutils}/bin/find ${home}/dl -mindepth 1 -mtime +14 -delete";
        };
      };
    };

    timers.bandit-dl-prune = {
      Unit.Description = "Daily ~/dl prune";
      Install.WantedBy = ["timers.target"];
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
