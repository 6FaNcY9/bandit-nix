{pkgs}:
pkgs.runCommand "werbung-watch-test" {
  nativeBuildInputs = [(pkgs.callPackage ./package.nix {})];
} ''
  mkdir bin
  # Stub: the Discord lookup prints $MEMBERS, every other call is an ntfy POST saved as posts-N.
  cat > bin/curl <<'STUB'
  #!${pkgs.runtimeShell}
  case " $* " in *discord.com*)
    [ -n "$MEMBERS" ] || exit 22
    printf '{"approximate_member_count":%s}\n' "$MEMBERS"; exit 0 ;;
  esac
  n=$(find . -maxdepth 1 -name 'posts-*' | wc -l)
  printf '%s\n' "$@" > "posts-$n"
  exit "''${CURL_EXIT:-0}"
  STUB
  chmod +x bin/curl
  export CURL=$PWD/bin/curl NTFY_TOKEN=t STATE_FILE=$PWD/state/members
  posts() { find . -maxdepth 1 -name 'posts-*' | wc -l; }

  # bump: reminds below STOP_AT, silent at it, auth header set
  MEMBERS=3 werbung-watch bump
  test "$(posts)" = 1
  grep -qx 'Title: Disboard: Zeit fuer /bump' posts-0
  grep -qx 'Authorization: Bearer t' posts-0
  MEMBERS=8 werbung-watch bump
  test "$(posts)" = 1

  # members: first run only records, no alert
  rm -f posts-*
  MEMBERS=3 werbung-watch members
  test "$(posts)" = 0
  test "$(cat state/members)" = 3
  # same count: no alert
  MEMBERS=3 werbung-watch members
  test "$(posts)" = 0
  # failed POST keeps the old count, so the next run alerts again
  CURL_EXIT=7 MEMBERS=4 werbung-watch members
  test "$(cat state/members)" = 3
  rm -f posts-*
  MEMBERS=4 werbung-watch members
  test "$(posts)" = 1
  grep -qx 'Title: Discord: neues Mitglied' posts-0
  test "$(cat state/members)" = 4
  # a drop updates silently, so a later rejoin alerts
  rm -f posts-*
  MEMBERS=2 werbung-watch members
  test "$(posts)" = 0
  test "$(cat state/members)" = 2

  # lookup failure: exit 0, no POST, state untouched
  MEMBERS= werbung-watch members 2>err
  test "$(posts)" = 0
  test "$(cat state/members)" = 2
  grep -q 'invite lookup failed' err

  # unknown mode fails
  MEMBERS=3 werbung-watch nope 2>/dev/null && exit 1

  touch $out
''
