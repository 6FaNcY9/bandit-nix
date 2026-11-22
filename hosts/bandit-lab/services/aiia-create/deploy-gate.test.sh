#!/usr/bin/env bash
# Laptop test for deploy-gate.sh with a fake podman/systemctl/curl and a real git push:
#   nix shell nixpkgs#git nixpkgs#util-linux -c bash deploy-gate.test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
mkdir -p "$t/home/out" "$t/state" "$t/bin" "$t/hooks"
cp "$here/deploy-pre-receive.sh" "$t/hooks/pre-receive"
sed -i '1i #!/usr/bin/env bash' "$t/hooks/pre-receive"
chmod +x "$t/hooks/pre-receive"

# the gate as deploy.nix builds it: strict mode, the exports, then the script
{
  echo 'set -euo pipefail'
  echo "export AIIA_DEPLOY_HOOKS=$t/hooks AIIA_REGISTRIES=/dev/null AIIA_APP_ORIGIN=https://aiia.at AIIA_ASSET_ORIGIN=https://cdn.aiia.at AIIA_TURNSTILE_SITE_KEY=key"
  cat "$here/deploy-gate.sh"
} >"$t/gate"
cat >"$t/bin/podman" <<'EOF'
#!/usr/bin/env bash
echo "podman $*" >>"$T/calls"
if [ "$1" = unshare ]; then
  shift 2
  case $1 in */readlink) [ -n "${SAME_NETNS:-}" ] && exec "$@"; echo "net:[999]"; exit 0 ;; esac
  exec "$@"
fi
case $1 in
build) [ -z "${FAIL_BUILD:-}" ] || exit 1 ;;
save) for a; do [ "${prev:-}" = -o ] && echo "archive" >"$a"; prev=$a; done ;;
esac
EOF
cat >"$t/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"$T/calls"
[ "$1" = is-active ] && { echo active; exit 0; }
if [ "$3" = aiia-deploy-install.service ]; then
  [ -f "$H/out/api.tar" ] && [ -f "$H/out/web.tar" ] && grep -Eq '^[0-9a-f]{40}$' "$H/out/sha" || exit 1
  echo "LIVE: test" >"$S/install.log"
fi
[ "$3" = aiia-deploy-logs@api.service ] && echo "log line" >"$S/logs-api.txt"
exit 0
EOF
printf '#!/usr/bin/env bash\nprintf 200\n' >"$t/bin/curl"
chmod +x "$t/bin/"*
export T=$t H=$t/home S=$t/state PATH="$t/bin:$PATH" AIIA_DEPLOY_HOME=$t/home AIIA_DEPLOY_STATE=$t/state \
  AIIA_DEPLOY_HOME_INODE=$(stat -c %i "$t/home")
gate() { SSH_ORIGINAL_COMMAND="$1" bash "$t/gate"; }

# help, refused commands
gate help | grep -q 'ssh aiia-lab deploy' || fail "help"
SSH_ORIGINAL_COMMAND= bash "$t/gate" | grep -q 'ssh aiia-lab deploy' || fail "no command"
for c in bash "deploy; id" "logs db" "logs api; id" "git-receive-pack '../etc'" "git-receive-pack '/srv/x.git'" "git-upload-archive 'aiia-generator.git'"; do
  if gate "$c" 2>/dev/null; then fail "accepted: $c"; fi
done

# without its own subvolume (disk limit) the gate takes nothing
if AIIA_DEPLOY_HOME_INODE=1 gate "git-receive-pack 'aiia-generator.git'" 2>/dev/null </dev/null; then fail "push without quota accepted"; fi
if AIIA_DEPLOY_HOME_INODE=1 gate deploy 2>/dev/null; then fail "deploy without quota accepted"; fi

# a real push through a fake ssh that hands the command to the gate like sshd does
printf '#!/usr/bin/env bash\nshift\nSSH_ORIGINAL_COMMAND="$*" exec bash %s\n' "$t/gate" >"$t/bin/fakessh"
chmod +x "$t/bin/fakessh"
export GIT_SSH_COMMAND=$t/bin/fakessh GIT_SSH_VARIANT=simple
git init -q "$t/src"
cd "$t/src"
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
git push -q aiia:aiia-generator.git HEAD:deploy/bandit-lab 2>/dev/null || fail "push deploy/bandit-lab"
[ "$(git -C "$t/home/aiia-generator.git" rev-parse deploy/bandit-lab)" = "$(git rev-parse HEAD)" ] || fail "pushed ref"
git push -q ssh://aiia/aiia-generator HEAD:refs/heads/deploy/bandit-lab 2>/dev/null || fail "push with ssh:// url"
if git push -q aiia:aiia-generator.git HEAD:main 2>/dev/null; then fail "push to main accepted"; fi
if git push -q aiia:aiia-generator.git HEAD:refs/tags/x 2>/dev/null; then fail "tag accepted"; fi
git -c user.name=t -c user.email=t@t commit -q --amend --allow-empty -m other
if git push -q -f aiia:aiia-generator.git HEAD:deploy/bandit-lab 2>/dev/null; then fail "force push accepted"; fi
if git push -q aiia:aiia-generator.git :deploy/bandit-lab 2>/dev/null; then fail "delete accepted"; fi
git fetch -q aiia:aiia-generator.git deploy/bandit-lab 2>/dev/null || fail "fetch"
git reset -q --hard FETCH_HEAD

# deploy: builds both images, hands the archives to the root unit, cleans up
mkdir -p api web config
echo x >config/x
echo x >api/Dockerfile
echo x >web/Dockerfile
git add -A
git -c user.name=t -c user.email=t@t commit -q -m "two images"
git push -q aiia:aiia-generator.git HEAD:deploy/bandit-lab 2>/dev/null || fail "push 2"
: >"$t/calls"
o=$(gate deploy) || fail "deploy failed: $o"
grep -q "deploy $(git rev-parse --short=7 HEAD): two images" <<<"$o" || fail "deploy header: $o"
grep -q "LIVE: test" <<<"$o" || fail "install log not shown: $o"
grep -q "build-arg NEXT_PUBLIC_TURNSTILE_SITE_KEY=key" "$t/calls" || fail "web build args"
grep -q "label org.opencontainers.image.revision=$(git rev-parse HEAD)" "$t/calls" || fail "revision label"
grep -q "systemctl --no-ask-password start aiia-deploy-install.service" "$t/calls" || fail "install unit"
grep -q "podman unshare --rootless-netns .*podman build" "$t/calls" || fail "build not inside the rootless network namespace"
grep -q "build --label org.opencontainers.image.revision=.* -f api/Dockerfile" "$t/calls" || fail "api Dockerfile not explicit"
[ ! -e "$t/home/out/api.tar" ] && [ ! -e "$t/home/out/web.tar" ] || fail "archives left behind"
[ -z "$(find "$t/home" -maxdepth 1 -name 'build.*')" ] || fail "build dir left behind"

# a symlinked build context is refused before any build
git rm -rq config
ln -s / config
git add -A
git -c user.name=t -c user.email=t@t commit -q -m "config is a symlink"
git push -q aiia:aiia-generator.git HEAD:deploy/bandit-lab 2>/dev/null || fail "push symlink tree"
: >"$t/calls"
if gate deploy >/dev/null 2>&1; then fail "symlinked config accepted"; fi
if grep -q " build " "$t/calls"; then fail "build ran on a symlinked context"; fi
rm config && mkdir config && echo x >config/x
git add -A
git -c user.name=t -c user.email=t@t commit -q -m "config is a directory again"
git push -q aiia:aiia-generator.git HEAD:deploy/bandit-lab 2>/dev/null || fail "push 3"

# no separate network namespace: no build
: >"$t/calls"
if SAME_NETNS=1 gate deploy >/dev/null 2>&1; then fail "deploy without a separate netns passed"; fi
if grep -q " build " "$t/calls"; then fail "build ran in the lab's network namespace"; fi

# a failed build changes nothing
: >"$t/calls"
if FAIL_BUILD=1 gate deploy >/dev/null 2>&1; then fail "deploy with failed build passed"; fi
if grep -q aiia-deploy-install "$t/calls"; then fail "install started after a failed build"; fi

# a second deploy while one runs is refused
exec 9>"$t/home/lock"
flock 9
if gate deploy >/dev/null 2>&1; then fail "parallel deploy accepted"; fi
exec 9>&-

# logs, status, rollback
gate "logs api" | grep -q "log line" || fail "logs api"
grep -q "start aiia-deploy-logs@api.service" "$t/calls" || fail "logs unit"
o=$(gate status) || fail "status rc: $o"; grep -q "pushed:   $(git rev-parse HEAD)" <<<"$o" || fail "status: $o"
gate rollback >/dev/null || fail "rollback"
grep -q "start aiia-deploy-rollback.service" "$t/calls" || fail "rollback unit"
echo "deploy-gate: all checks passed"
