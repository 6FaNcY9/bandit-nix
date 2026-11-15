# Wiring check for mrija-watch: stub rsync/dig/curl on PATH (via the RSYNC/DIG/
# CURL env overrides the code honours), run collect+digest against a synthetic
# Maildir and two manifests, and assert the instant/digest behaviour and the
# privacy rule. Mirrors jerry-box/report-test.nix. No real mail, no network.
{pkgs}: let
  watcher = pkgs.callPackage ./package.nix {};
  # The committed synthetic Maildir; its one password-test subject carries a
  # fake token that must never reach a post.
  pwToken = "Hunter2SecretPW";
in
  pkgs.runCommand "mrija-watch-test" {
    nativeBuildInputs = [watcher pkgs.coreutils pkgs.findutils pkgs.gnugrep];
    maildir = ./testdata/maildir;
  } ''
    mkdir bin
    # rsync stub: ignore the args, print the manifest named by RSYNC_MANIFEST.
    cat > bin/rsync <<'STUB'
    #!${pkgs.runtimeShell}
    cat "$RSYNC_MANIFEST"
    STUB
    # dig stub: no records, so DNS never changes between runs.
    cat > bin/dig <<'STUB'
    #!${pkgs.runtimeShell}
    exit 0
    STUB
    # curl stub: record headers + the --data-raw body to posts-N, honour CURL_EXIT.
    cat > bin/curl <<'STUB'
    #!${pkgs.runtimeShell}
    n=$(find . -maxdepth 1 -name 'posts-*' | wc -l)
    body=""
    prev=""
    for a in "$@"; do
      [ "$prev" = "--data-raw" ] && body="$a"
      prev="$a"
    done
    { printf '%s\n' "$@"; echo ---; printf '%s\n' "$body"; } > "posts-$n"
    exit "''${CURL_EXIT:-0}"
    STUB
    chmod +x bin/rsync bin/dig bin/curl
    export RSYNC=$PWD/bin/rsync DIG=$PWD/bin/dig CURL=$PWD/bin/curl
    export NTFY_URL=http://127.0.0.1:2586 NTFY_TOPIC=mrija NTFY_TOKEN=t
    export MRIJA_REMOTE=x@host:www/ MRIJA_KEY=/dev/null MRIJA_DNS_NAME=mrija.org
    # No MRIJA_HTTP_URL: skip the network reachability probe in the sandbox.

    posts() { find . -maxdepth 1 -name 'posts-*' | wc -l; }

    printf '%s\n' \
      'drwxr-xr-x 4096 2026/01/01 00:00:00 wp-content' \
      '-rw-r--r-- 100 2026/01/01 00:00:00 wp-content/plugins/elementor/foo.js' \
      '-rw-r--r-- 50 2026/01/01 00:00:00 index.php' > manifest1
    cp manifest1 manifest2
    printf '%s\n' \
      '-rw-r--r-- 10 2026/02/01 00:00:00 wp-content/mu-plugins/evil/index.php' >> manifest2

    # --- Scenario A + D: a planted mu-plugins file pushes high priority, and no
    # post ever contains the password token from the Maildir subject.
    export STATE_DIR=$PWD/sx MRIJA_MAILDIR=$maildir
    RSYNC_MANIFEST=$PWD/manifest1 mrija-watch collect   # baseline
    rm -f posts-*
    RSYNC_MANIFEST=$PWD/manifest2 mrija-watch collect   # planted file
    grep -rq 'mu-plugins/evil/index.php' posts-* || { echo "A: no mu-plugins post"; exit 1; }
    grep -rlq 'Priority: high' posts-* || { echo "A: not high priority"; exit 1; }
    grep -rl 'Title: Mrija:' posts-* >/dev/null || { echo "A: no Mrija title"; exit 1; }
    if grep -rq "${pwToken}" posts-*; then echo "D: password token leaked"; exit 1; fi

    # --- Scenario B: an all-clean run with an empty Maildir -> the digest posts
    # exactly one message that says "ruhig".
    rm -f posts-*
    mkdir -p emptymail
    export STATE_DIR=$PWD/sy MRIJA_MAILDIR=$PWD/emptymail
    RSYNC_MANIFEST=$PWD/manifest1 mrija-watch collect   # quiet baseline, 0 posts
    test "$(posts)" = 0 || { echo "B: baseline should not post"; exit 1; }
    mrija-watch digest
    test "$(posts)" = 1 || { echo "B: digest must post exactly once"; exit 1; }
    grep -rq 'ruhig' posts-* || { echo "B: digest not quiet"; exit 1; }

    # --- Scenario C: curl fails (CURL_EXIT=7) on a run with an instant -> the
    # command still exits 0 and the web manifest state is not advanced.
    rm -f posts-*
    export STATE_DIR=$PWD/sz MRIJA_MAILDIR=$PWD/emptymail
    RSYNC_MANIFEST=$PWD/manifest1 mrija-watch collect   # baseline -> state = manifest1
    rm -f posts-*
    CURL_EXIT=7 RSYNC_MANIFEST=$PWD/manifest2 mrija-watch collect   # must not crash
    grep -q 'mu-plugins' sz/state.json && { echo "C: state advanced despite push failure"; exit 1; }
    grep -q 'wp-content/plugins/elementor' sz/state.json || { echo "C: baseline state lost"; exit 1; }

    touch $out
  ''
