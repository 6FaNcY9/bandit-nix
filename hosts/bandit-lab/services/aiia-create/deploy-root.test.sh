#!/usr/bin/env bash
# Laptop test for deploy-root.sh with a fake podman/skopeo/systemctl/curl (image tags are files):
#   nix shell nixpkgs#util-linux -c bash deploy-root.test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
mkdir -p "$t/bin" "$t/in" "$t/state" "$t/data/redis" "$t/tags" "$t/work"
echo dump >"$t/data/redis/dump.rdb"
{
  echo 'set -euo pipefail'
  cat "$here/deploy-root.sh"
} >"$t/root"

# fake image store: tags/<name with / and : as _> holds "<id> <revision>"
cat >"$t/bin/podman" <<'EOF'
#!/usr/bin/env bash
echo "podman $*" >>"$T/calls"
f() { echo "$T/tags/$(tr '/:' '__' <<<"$1")"; }
# like podman, an image stays (by id) when its last name moves away: $T/all lists every image seen
find_img() { if [ -f "$(f "$1")" ]; then cat "$(f "$1")"; else grep -h "^$1 " "$T/all" 2>/dev/null | head -1; fi; }
case "$1 $2" in
"image inspect")
  img=$(find_img "$5"); [ -n "$img" ] || exit 1
  case $4 in *Labels*) echo "${img#* }" ;; *) echo "${img%% *}" ;; esac ;;
"tag "*) img=$(find_img "$2"); [ -n "$img" ] || exit 1; echo "$img" >"$(f "$3")" ;;
"untag "*) rm -f "$(f "$3")" ;;
"rmi "*) ;;
"exec aiia-create-redis") [ -z "${FAIL_SAVE:-}" ] || exit 1 ;;
esac
exit 0
EOF
cat >"$t/bin/skopeo" <<'EOF'
#!/usr/bin/env bash
echo "skopeo $*" >>"$T/calls"
src=${3#docker-archive:} dst=${4#containers-storage:}
cp "$src" "$T/tags/$(tr '/:' '__' <<<"$dst")"
cat "$src" >>"$T/all"
EOF
cat >"$t/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"$T/calls"
[ "$1" = is-active ] && echo active
exit 0
EOF
# curl answers 200 unless the api image running now is the one named in BAD_ID
cat >"$t/bin/curl" <<'EOF'
#!/usr/bin/env bash
cur=$(cut -d' ' -f1 "$T/tags/ghcr.io_6fancy9_aiia-generator-api_main" 2>/dev/null)
if [ -n "${BAD_ID:-}" ] && [ "$cur" = "$BAD_ID" ]; then printf 500; else printf 200; fi
EOF
printf '#!/usr/bin/env bash\necho "journal of $2"\n' >"$t/bin/journalctl"
chmod +x "$t/bin/"*
export T=$t PATH="$t/bin:$PATH" AIIA_DEPLOY_IN=$t/in AIIA_DEPLOY_STATE=$t/state AIIA_REDIS_PARENT=$t/data \
  AIIA_DEPLOY_GROUP=$(id -gn) AIIA_CHECK_TRIES=2 AIIA_CHECK_SLEEP=0 AIIA_DEPLOY_LOCK=$t/lock \
  AIIA_DEPLOY_WORK=$t/work AIIA_READ_AS=env AIIA_KEEP_SNAPSHOTS=5
root() { bash "$t/root" "$@"; }
tag() { cut -d' ' -f1 "$t/tags/ghcr.io_6fancy9_aiia-generator-$1" 2>/dev/null || echo none; }
sha1=1111111111111111111111111111111111111111 sha2=2222222222222222222222222222222222222222
stage() { # id prefix, commit: archives as the gate leaves them
  echo "$1-api $2" >"$t/in/api.tar"
  echo "$1-web $2" >"$t/in/web.tar"
  echo "$2" >"$t/in/sha"
}
echo "old-api unknown" >"$t/tags/ghcr.io_6fancy9_aiia-generator-api_main"
echo "old-web unknown" >"$t/tags/ghcr.io_6fancy9_aiia-generator-web_main"
cat "$t"/tags/* >"$t/all"

# refused input stops before anything is touched
echo "not a sha" >"$t/in/sha"
: >"$t/calls"
if root install >/dev/null; then fail "bad sha accepted"; fi
if grep -q "systemctl stop" "$t/calls"; then fail "site stopped for a bad sha"; fi
stage n1 "$sha1"
ln -sf "$t/elsewhere" "$t/in/web.tar"
if root install >/dev/null; then fail "unreadable archive accepted"; fi
rm -f "$t/in/web.tar"
stage n1 "$sha1"
if AIIA_MAX_ARCHIVE=10 root install >/dev/null; then fail "archive above the size limit accepted"; fi
if grep -q "skopeo" "$t/calls"; then fail "skopeo ran on a refused archive"; fi
if root bogus 2>/dev/null; then fail "unknown verb accepted"; fi

# a good deploy: new images live, old ones kept as :prev, Redis copied, state written
stage n1 "$sha1"
: >"$t/calls"
o=$(root install) || fail "install failed: $o"
grep -q "LIVE: 1111111" <<<"$o" || fail "install output: $o"
[ "$(tag api_main) $(tag web_main) $(tag api_prev) $(tag web_prev)" = "n1-api n1-web old-api old-web" ] || fail "tags after deploy"
[ "$(tag api_new)" = none ] || fail ":new left behind"
ls "$t/data" | grep -q "^redis-deploy-.*-1111111$" || fail "no Redis snapshot"
grep -q "deployed: $sha1" "$t/state/state" && grep -q "previous: unknown" "$t/state/state" || fail "state: $(cat "$t/state/state")"
grep -q "1111111 ok" "$t/state/deploys.log" || fail "deploys.log"
grep -q "LIVE: 1111111" "$t/state/install.log" || fail "install.log"
grep -q "systemctl stop aiia-create-web aiia-create-api" "$t/calls" || fail "site not stopped for the snapshot"

# a deploy that fails its check goes back to the images that ran before
stage n2 "$sha2"
if o=$(BAD_ID=n2-api root install); then fail "failed check passed"; fi
grep -q "ROLLED BACK: 2222222" <<<"$o" || fail "rollback output: $o"
[ "$(tag api_main) $(tag web_main) $(tag api_prev) $(tag web_prev)" = "n1-api n1-web old-api old-web" ] || fail "tags after the way back: the older :prev must stay"
grep -q "2222222 rolled-back" "$t/state/deploys.log" || fail "deploys.log rolled-back"

# a failed Redis snapshot deploys nothing and starts the old version again
stage n3 "$sha2"
: >"$t/calls"
if FAIL_SAVE=1 root install >/dev/null; then fail "failed snapshot passed"; fi
[ "$(tag api_main)" = n1-api ] || fail "tags changed after a failed snapshot"
grep -q "systemctl restart aiia-create-api aiia-create-web" "$t/calls" || fail "old version not started again"

# a good deploy, then rollback swaps, a second rollback goes forward again
stage n4 "$sha2"
: >"$t/calls"
root install >/dev/null || fail "install n4"
grep -q "podman rmi old-api" "$t/calls" || fail "the image that fell off :prev was not removed"
if grep -q "image prune" "$t/calls"; then fail "root must not prune all dangling images"; fi
o=$(root rollback) || fail "rollback: $o"
[ "$(tag api_main) $(tag api_prev)" = "n1-api n4-api" ] || fail "tags after rollback: $(tag api_main) $(tag api_prev)"
root rollback >/dev/null || fail "rollback 2"
[ "$(tag api_main) $(tag api_prev)" = "n4-api n1-api" ] || fail "tags after second rollback"

# a rollback to a version that fails its check keeps the current one
if o=$(BAD_ID=n1-api root rollback); then fail "failing rollback passed"; fi
grep -q "NOT ROLLED BACK" <<<"$o" || fail "failed rollback output: $o"
[ "$(tag api_main) $(tag api_prev)" = "n4-api n1-api" ] || fail "tags after a failed rollback"

# only five deploy snapshots are kept
for i in 1 2 3 4 5 6 7; do mkdir -p "$t/data/redis-deploy-20200101-00000$i-aaaaaaa"; done
stage n5 "$sha1"
root install >/dev/null || fail "install n5"
[ "$(find "$t/data" -maxdepth 1 -name 'redis-deploy-*' | wc -l)" = 5 ] || fail "snapshot count"

# logs
root logs api >/dev/null || fail "logs api"
grep -q "journal of aiia-create-api" "$t/state/logs-api.txt" || fail "logs file"
if root logs db 2>/dev/null; then fail "logs db accepted"; fi
echo "deploy-root: all checks passed"
