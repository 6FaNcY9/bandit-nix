#!/usr/bin/env bash
# Test for tools/ship-claude against throw-away repos: bare origin with main,
# a work clone with a dirty file and a feature commit. Run: tools/ship-claude.test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
git init -q --bare -b main "$t/origin.git"
git clone -q "$t/origin.git" "$t/work" 2>/dev/null
cd "$t/work"
echo a >f; git add f; git commit -qm base; git push -q origin main
git checkout -qb feat; echo b >g; git add g; git commit -qm feature; sha=$(git rev-parse HEAD)
git checkout -q main; echo dirty >f   # uncommitted work that must not leak
before=$(git -C "$t/origin.git" rev-parse main)

out=$("$here/ship-claude" --dry-run --repo "$t/work" "$sha")
grep -q "git -C .* push origin HEAD:main" <<<"$out"
wt=$(sed -n 's/^ready: .* in //p' <<<"$out")
[[ $(git -C "$wt" show HEAD:g) == b ]]                  # feature landed
[[ $(git -C "$wt" show HEAD:f) == a ]]                  # dirty file did not
[[ $(git -C "$t/origin.git" rev-parse main) == "$before" ]]  # nothing pushed
[[ $(cat "$t/work/f") == dirty ]]                       # work tree untouched
git -C "$t/work" worktree remove --force "$wt"

# bad sha: fails and leaves no worktree behind
if "$here/ship-claude" --dry-run --repo "$t/work" deadbeef 2>/dev/null; then echo "bad sha accepted" >&2; exit 1; fi
[[ $(git -C "$t/work" worktree list | wc -l) -eq 1 ]]
echo ok
