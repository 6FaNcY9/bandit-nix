{pkgs}:
pkgs.runCommand "jerry-report-test" {nativeBuildInputs = [(pkgs.callPackage ./report.nix {})];} ''
  mkdir bin
  # CURL overrides the binary: writeShellApplication puts its own curl first on PATH.
  cat > bin/curl <<'STUB'
  #!${pkgs.runtimeShell}
  n=$(ls posts-* 2>/dev/null | wc -l)
  { printf '%s\n' "$@"; echo ---; cat; } > "posts-$n"
  exit "''${CURL_EXIT:-0}"
  STUB
  chmod +x bin/curl
  export CURL=$PWD/bin/curl NTFY_TOKEN=t STATE_FILE=$PWD/cursor

  rec() { printf '{"_AUDIT_TYPE_NAME":"SYSCALL","__CURSOR":"s=%s","MESSAGE":"audit(1.0:%s): arch=c000003e syscall=59 success=yes exit=%s a0=1 comm=\\"%s\\" exe=\\"/nix/store/x/%s\\" key=\\"jerry\\""}\n' "$1" "$1" "$2" "$3" "$3"; }
  { rec 1 0 python3; rec 2 1 python3; rec 3 0 ls; } > a.json

  # A: grouped body, title, cursor advanced
  JERRY_JOURNAL_FILE=a.json jerry-report
  grep -qx 'Title: Jerry box: 3 processes' posts-0
  test "$(sed -n '/^---$/,$p' posts-0 | tail -n +2)" = "$(printf '2x python3 (1 failed)\n1x ls (0 failed)')"
  test "$(cat cursor)" = "s=3"

  # B: empty input, no POST
  : > b.json
  JERRY_JOURNAL_FILE=b.json jerry-report
  test "$(ls posts-* | wc -l)" = 1

  # C: curl failure, exit 0, cursor not advanced
  rm cursor
  CURL_EXIT=7 JERRY_JOURNAL_FILE=a.json jerry-report
  test ! -e cursor

  touch $out
''
