#!/usr/bin/env bash
# Install the hand-off memory for the Claude Code CLI of this checkout.
# Usage (from anywhere): bash docs/runbooks/minecraft/handoff-memory/install.sh [repo-root]
# Copies the three memory files and adds their lines to MEMORY.md (idempotent).
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${1:-$src/../../../..}" && pwd)"
key="$(printf '%s' "$repo" | sed 's|[/.]|-|g')"
dest="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$key/memory"

mkdir -p "$dest"
touch "$dest/MEMORY.md"

add_index() { # file, one-line hook
  grep -qF "($1)" "$dest/MEMORY.md" || printf -- '- [%s](%s) — %s\n' "$2" "$1" "$3" >> "$dest/MEMORY.md"
}

for f in project_mcbots_state.md reference_ship_and_environment.md feedback_deploy_and_overnight_rules.md; do
  if [ -e "$dest/$f" ] && ! cmp -s "$src/$f" "$dest/$f"; then
    cp "$dest/$f" "$dest/$f.bak"
    echo "kept backup: $dest/$f.bak"
  fi
  cp -f "$src/$f" "$dest/$f"
done

add_index project_mcbots_state.md "mcbots state" "bots state, read HANDOFF + AUTOPILOT-GOAL"
add_index reference_ship_and_environment.md "ship and environment" "how to ship to bandit-lab, laptop quirks"
add_index feedback_deploy_and_overnight_rules.md "owner working rules" "language, deploy/secret boundaries, unattended runs"

echo "installed into $dest"
