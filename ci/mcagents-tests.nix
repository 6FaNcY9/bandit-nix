# The mcagents unit tests (tools/mcagents/*.test.js and lessons.js's self-check): plain Node, no network,
# no npm dependencies. Until 2026-10-11 they only ran by hand. The repo layout is rebuilt because the
# tests load mcbots modules and blueprints relative to tools/mcagents.
{pkgs}:
pkgs.runCommand "mcagents-tests" {nativeBuildInputs = [pkgs.nodejs];} ''
  mkdir -p tools hosts/bandit-lab/services
  cp -r ${../tools/mcagents} tools/mcagents
  cp -r ${../hosts/bandit-lab/services/mcbots} hosts/bandit-lab/services/mcbots
  chmod -R u+w tools hosts
  cd tools/mcagents
  for t in *.test.js; do
    echo "== $t"
    node "$t"
  done
  node lessons.js
  touch $out
''
