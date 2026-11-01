{pkgs}:
pkgs.runCommand "jerry-report-test" {
  nativeBuildInputs = [(pkgs.callPackage ./report.nix {}) (pkgs.callPackage ./watch-wrapper.nix {})];
} ''
  mkdir bin
  # CURL overrides the binary: writeShellApplication puts its own curl first on PATH.
  cat > bin/curl <<'STUB'
  #!${pkgs.runtimeShell}
  n=$(ls posts-* 2>/dev/null | wc -l)
  { printf '%s\n' "$@"; echo ---; case " $* " in *" @- "*) cat ;; esac; } > "posts-$n"
  exit "''${CURL_EXIT:-0}"
  STUB
  chmod +x bin/curl
  export CURL=$PWD/bin/curl NTFY_TOKEN=t STATE_FILE=$PWD/cursor
  posts() { ls posts-* 2>/dev/null | wc -l; }
  body() { sed -n '/^---$/,$p' "$1" | tail -n +2; }

  rec() { printf '{"_AUDIT_TYPE_NAME":"SYSCALL","__CURSOR":"s=%s","MESSAGE":"audit(1.0:%s): arch=c000003e syscall=59 success=yes exit=%s a0=1 comm=%s exe=\\"/nix/store/x/bin\\" key=\\"%s\\""}\n' "$1" "$1" "$2" "$3" "$4"; }
  {
    rec 1 0 '\"python3\"' jerry
    rec 2 1 '\"python3\"' jerry
    echo '{"_AUDIT_TYPE_NAME":"PROCTITLE","__CURSOR":"s=3","MESSAGE":"audit(1.0:2): proctitle=7079 key=\"jerry\""}'
    rec 4 0 '\"other\"' other
    rec 5 0 '\"ls\"' jerry
    rec 6 0 6D7920746F6F6C jerry
  } > a.json

  # A: filter, hex comm, deterministic order, title matches body, auth header, cursor
  JERRY_JOURNAL_FILE=a.json jerry-report
  grep -qx 'Title: Jerry box: 4 processes' posts-0
  grep -qx 'Authorization: Bearer t' posts-0
  test "$(body posts-0)" = "$(printf '2x python3 (1 failed)\n1x ls (0 failed)\n1x my tool (0 failed)')"
  test "$(cat cursor)" = "s=6"

  # B: empty input, no POST
  : > b.json
  JERRY_JOURNAL_FILE=b.json jerry-report
  test "$(posts)" = 1

  # C: curl failure, exit 0, cursor not advanced
  rm cursor
  CURL_EXIT=7 JERRY_JOURNAL_FILE=a.json jerry-report
  test ! -e cursor

  # watch: one stdin filter per mode; EOF must fail the unit so systemd restarts it
  rm -f posts-*
  printf 'noise\nAccepted publickey for root from 10.251.0.1\nmore\n' | jerry-watch ssh && exit 1
  test "$(posts)" = 1
  grep -qx 'Title: Jerry box: ssh login' posts-0
  grep -qx 'Authorization: Bearer t' posts-0
  grep -qx 'Accepted publickey for root from 10.251.0.1' posts-0 # -d body is an argument

  rm -f posts-*
  printf 'jerry POST /a\nother POST /b\njerry POST /c\njerry GET /d\njerry POST /e\n' > r.txt
  DEBOUNCE_SECONDS=100000 jerry-watch restic < r.txt && exit 1
  test "$(posts)" = 1
  grep -qx 'Title: Jerry restic: backup activity' posts-0
  grep -qx 'jerry POST /a' posts-0
  rm -f posts-*
  DEBOUNCE_SECONDS=0 jerry-watch restic < r.txt && exit 1
  test "$(posts)" = 3

  # curl failure must not stop the loop; EOF still exits 1
  rm -f posts-*
  rc=0
  CURL_EXIT=7 DEBOUNCE_SECONDS=0 jerry-watch restic < r.txt 2>err || rc=$?
  test "$rc" = 1
  test "$(posts)" = 3

  touch $out
''
