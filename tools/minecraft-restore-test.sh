#!/usr/bin/env bash
# Restore drill for a Minecraft backup (docs/runbooks/minecraft/MIGRATION.md).
#   tools/minecraft-restore-test.sh ARCHIVE [IMAGE]
# ARCHIVE is a minecraft-*.tar.zst from minecraft-backup (or a data.tar.gz from a
# manual cold backup). The archive is verified against its .sha256 file when one
# sits next to it, extracted into a NEW temporary directory (never over
# /srv/containers/minecraft/data) and booted as a throwaway Paper container with
# NO published port (it may download Paper's vanilla jar and BlueMap's client
# jar, which backups exclude). The script then lists the dimensions that loaded,
# the plugins that enabled and the player files, and removes only what it
# created. It does not touch the production container or data.
set -euo pipefail

archive=$(realpath "${1:?usage: minecraft-restore-test.sh ARCHIVE [IMAGE]}")
# Same pinned image as the production container (hosts/bandit-lab/services/minecraft).
image=${2:-itzg/minecraft-server@sha256:769a826c340586e9d483a0eb6437b8e2c3611aea6a115ff072a2fe372d43e2be}
name=mc-restore-test-$$
work=$(mktemp -d "${TMPDIR:-/tmp}/mc-restore-XXXXXX")
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  # Files are owned by the container user; delete them from inside a container.
  docker run --rm --entrypoint sh -v "$work":/w "$image" -c 'find /w -mindepth 1 -delete' >/dev/null 2>&1 || true
  rmdir "$work" 2>/dev/null || true
}
trap cleanup EXIT

if [ -f "$archive.sha256" ]; then
  (cd "$(dirname "$archive")" && sha256sum --check "$(basename "$archive").sha256")
else
  echo "no .sha256 next to the archive: checksum not verified (record one before relying on it)" >&2
fi

echo "== extracting into $work"
docker run --rm --entrypoint sh -v "$work":/restore -v "$(dirname "$archive")":/in:ro "$image" -c '
  set -e
  cd /restore
  case "$1" in
    *.zst) tar --use-compress-program=unzstd -xf "/in/$2" --strip-components=1 ;;
    *) tar -xf "/in/$2" --strip-components=1 ;;
  esac
  chown -R 1000:1000 /restore
  test -f /restore/server.properties
  jar=$(ls /restore/paper-*.jar | head -1); echo "server jar: $jar"
' sh "$archive" "$(basename "$archive")"

jar=$(docker run --rm --entrypoint sh -v "$work":/r "$image" -c 'basename "$(ls /r/paper-*.jar | head -1)"')
echo "== booting throwaway server from $jar (no published ports)"
docker run -d --name "$name" --memory 4g --cpus 2 \
  -e EULA=TRUE -e TYPE=CUSTOM -e CUSTOM_SERVER="/data/$jar" -e MEMORY=2G \
  -e ENABLE_RCON=false -e CREATE_CONSOLE_IN_PIPE=true \
  -v "$work":/data "$image" >/dev/null

for _ in $(seq 1 90); do
  if docker logs "$name" 2>&1 | grep -q 'Done ('; then break; fi
  if [ "$(docker inspect --format '{{.State.Running}}' "$name")" != true ]; then
    echo "server exited early:" >&2
    docker logs --tail 40 "$name" >&2
    exit 1
  fi
  sleep 3
done
docker logs "$name" 2>&1 | grep -q 'Done (' || { echo "server did not finish starting in time" >&2; exit 1; }

echo "== result"
docker logs "$name" 2>&1 | grep -E 'Loading Paper|Running Java' | sed 's/^/  /'
echo "  plugins enabled:"
docker logs "$name" 2>&1 | grep -oE '\[[A-Za-z]+\] Enabling [A-Za-z]+ v[0-9.]+' | sed 's/^.*Enabling /    /' | sort -u
echo "  dimensions:"
docker exec "$name" sh -c 'cd /data/world/dimensions/minecraft 2>/dev/null && for d in *; do echo "    $d: $(find "$d/region" -name "*.mca" | wc -l) region files"; done'
echo "  player files: $(docker exec "$name" sh -c 'ls /data/world/players/data 2>/dev/null | wc -l') in players/data"
docker exec --user 1000 "$name" mc-send-to-console list >/dev/null
sleep 2
docker logs --since 5s "$name" 2>&1 | grep 'players online' | sed 's/^/  /' || true
errors=$(docker logs "$name" 2>&1 | grep -cE 'ERROR\]|FATAL\]' || true)
echo "  ERROR lines in log: $errors"
docker stop "$name" >/dev/null
echo "restore drill finished; temporary data removed"
