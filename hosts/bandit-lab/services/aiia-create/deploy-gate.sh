# aiia-gate: the forced command of Albert's deploy key (user aiia-deploy, deploy.nix).
# It is the only program that key can run. What it accepts:
#   git push lab deploy/bandit-lab   git-receive-pack, only that branch, fast-forward only
#   git fetch lab                    git-upload-pack
#   deploy                           build both images from the pushed branch (rootless), then
#                                    aiia-deploy-install.service loads them, saves Redis, restarts,
#                                    checks and goes back to the old images if the check fails
#   rollback                         swap to the images that ran before (data is not touched)
#   status                           pushed and deployed commit, units, last check
#   logs api|web                     the last 300 journal lines of that container
# Everything else is refused. Test: deploy-gate.test.sh.
home=${AIIA_DEPLOY_HOME:-/srv/aiia-deploy}
state=${AIIA_DEPLOY_STATE:-/var/lib/aiia-deploy}
repo=$home/aiia-generator.git
out=$home/out
branch=deploy/bandit-lab
cmd=${SSH_ORIGINAL_COMMAND:-help}
# Everything this account writes must land in its own btrfs subvolume, whose qgroup caps the
# disk use (the rest of the lab shares one filesystem). A subvolume's root has inode 256.
subvol_inode=${AIIA_DEPLOY_HOME_INODE:-256}
build_timeout=${AIIA_BUILD_TIMEOUT:-30m}
export TMPDIR=$home/tmp

die() {
  echo "aiia-gate: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
aiia deploy on bandit-lab. Commands:
  git push aiia-lab deploy/bandit-lab   send the code (only this branch, no force push)
  ssh aiia-lab deploy                   build and go live; goes back by itself if the check fails
  ssh aiia-lab rollback                 back to the version that ran before (code only, not data)
  ssh aiia-lab status                   what is pushed, what is live, the last check
  ssh aiia-lab logs api                 last 300 log lines (api or web)
EOF
}

need_quota() {
  [ "$(stat -c %i "$home")" = "$subvol_inode" ] || die "$home is not its own subvolume (disk limit missing): ask vino"
  mkdir -p "$TMPDIR"
}

init_repo() {
  [ -d "$repo" ] || git init -q --bare "$repo"
  git -C "$repo" config receive.denyNonFastForwards true
  git -C "$repo" config receive.denyDeletes true
  git -C "$repo" config receive.fsckObjects true
  git -C "$repo" config receive.maxInputSize 1g
  git -C "$repo" config core.hooksPath "$AIIA_DEPLOY_HOOKS"
  git -C "$repo" symbolic-ref HEAD "refs/heads/$branch"
}

lock() {
  exec 9>"$home/lock"
  flock -n 9 || die "a deploy or rollback is already running"
}

root_unit() { # unit, log file: start the fixed root unit, show what it wrote
  local rc=0
  systemctl --no-ask-password start "$1" || rc=$?
  [ -f "$2" ] && cat "$2"
  return "$rc"
}

build() { # what, podman build arguments...: one image, with a time limit
  local what=$1 pm outer inner
  shift
  pm=$(command -v podman)
  # fail closed: the build must really run in another network namespace than the lab's
  outer=$(readlink /proc/self/ns/net)
  inner=$("$pm" unshare --rootless-netns "$(command -v readlink)" /proc/self/ns/net) || inner=
  [ -n "$inner" ] && [ "$inner" != "$outer" ] || die "the rootless network namespace is missing, no build: ask vino"
  echo "building $what image ..."
  # In podman's rootless network namespace, "RUN --network=host" in a Dockerfile means that
  # namespace (behind pasta, so behind the firewall filter on this uid), not the lab's network.
  (cd "$work/src" && nice -n 10 timeout -k 1m "$build_timeout" "$pm" unshare --rootless-netns "$pm" build "$@") ||
    die "$what image build failed or took longer than $build_timeout, nothing changed on the site"
}

deploy() {
  need_quota
  lock
  local sha rc=0 p
  sha=$(git -C "$repo" rev-parse -q --verify "refs/heads/$branch^{commit}") || die "nothing pushed yet: git push aiia-lab $branch"
  echo "deploy ${sha:0:7}: $(git -C "$repo" log -1 --format=%s "$sha")"
  work=$(mktemp -d "$home/build.XXXXXX") # global: the EXIT trap runs after deploy returns
  trap 'rm -rf "$work"' EXIT
  mkdir "$work/src"
  git -C "$repo" archive "$sha" | tar -x -C "$work/src"
  # a symlink here would make podman use a directory outside the checkout as build context
  for p in api web config api/Dockerfile web/Dockerfile; do
    [ ! -L "$work/src/$p" ] || die "refused: $p is a symlink"
  done
  export CONTAINERS_REGISTRIES_CONF=$AIIA_REGISTRIES
  local label=org.opencontainers.image.revision=$sha api=localhost/aiia-api:${sha:0:12} web=localhost/aiia-web:${sha:0:12}
  build api --label "$label" --build-context config=./config -f api/Dockerfile -t "$api" ./api
  build web --format docker --label "$label" -f web/Dockerfile -t "$web" \
    --build-arg APP_ORIGIN="$AIIA_APP_ORIGIN" \
    --build-arg ASSET_ORIGIN="$AIIA_ASSET_ORIGIN" \
    --build-arg NEXT_PUBLIC_TURNSTILE_SITE_KEY="$AIIA_TURNSTILE_SITE_KEY" .
  rm -f "$out"/api.tar "$out"/web.tar "$out"/sha
  podman save --format docker-archive -o "$out/api.tar" "$api"
  podman save --format docker-archive -o "$out/web.tar" "$web"
  printf '%s\n' "$sha" >"$out/sha"
  root_unit aiia-deploy-install.service "$state/install.log" || rc=$?
  rm -f "$out"/api.tar "$out"/web.tar
  podman image rm -f "$api" "$web" >/dev/null 2>&1 || true
  podman image prune -f --filter until=168h >/dev/null 2>&1 || true
  return "$rc"
}

status() {
  local pushed u
  pushed=$(git -C "$repo" rev-parse -q --verify "refs/heads/$branch" 2>/dev/null) || pushed=none
  echo "pushed:   $pushed"
  if [ -f "$state/state" ]; then cat "$state/state"; else echo "deployed: nothing through this gate yet"; fi
  for u in aiia-create-redis aiia-create-api aiia-create-web; do
    printf '%-18s %s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null || true)"
  done
  [ -f "$state/install.log" ] && { echo "last check:"; grep -E '^check ' "$state/install.log" | tail -n 1 || true; }
  [ -f "$state/deploys.log" ] && { echo "last deploys:"; tail -n 5 "$state/deploys.log"; }
  return 0
}

case $cmd in
"git-receive-pack '"*"'" | "git-upload-pack '"*"'")
  path=${cmd#* \'}
  path=${path%\'}
  path=${path#/}
  path=${path%/}
  case $path in
  aiia-generator | aiia-generator.git) ;;
  *) die "only the repository aiia-generator.git is here" ;;
  esac
  need_quota
  init_repo
  exec "${cmd%% *}" "$repo"
  ;;
deploy) deploy ;;
rollback)
  lock
  root_unit aiia-deploy-rollback.service "$state/rollback.log"
  ;;
status) status ;;
"logs api" | "logs web") root_unit "aiia-deploy-logs@${cmd#logs }.service" "$state/logs-${cmd#logs }.txt" ;;
help | "") usage ;;
*)
  usage >&2
  die "refused: $cmd"
  ;;
esac
