#!/usr/bin/env bash
# Owner-run peer restore: scratch files and throwaway containers only.
set -euo pipefail
umask 077
role=${1:?usage: restore-drill.sh lab|laptop [snapshot-id]}
snapshot=${2:-latest}
case "$role" in
  lab) source_host=bandit-lab; includes=(/var/backup/restic-staging-peer /var/backup/postgresql /srv/containers/aiia/content-data) ;;
  laptop) source_host=bandit; includes=(/home/vino/Documents) ;;
  *) echo 'role must be lab or laptop' >&2; exit 2 ;;
esac
[[ "$snapshot" == latest || "$snapshot" =~ ^[a-fA-F0-9]{8,64}$ ]] || { echo 'invalid snapshot ID' >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/restore-drill-XXXXXXXX")
prefix=$(basename "$work")
containers=()
cleanup() {
  local status=$? failed=0
  trap - EXIT
  for name in "${containers[@]}"; do
    if ! docker rm -fv "$name" >"$work/cleanup.log" 2>&1; then
      grep -q 'No such container' "$work/cleanup.log" || failed=1
    fi
  done
  if (( failed )); then
    echo "cleanup failed; owner must remove ${containers[*]} and $work" >&2
    exit 1
  fi
  rm -rf -- "$work" || { echo "scratch cleanup failed: $work" >&2; exit 1; }
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { echo "$1; private diagnostics are removed with scratch" >&2; exit 1; }

select=(--latest 1)
[[ "$snapshot" == latest ]] || select=("$snapshot")
restic-peer --no-cache --no-lock snapshots --json --host "$source_host" "${select[@]}" >"$work/snapshots.json" 2>"$work/restic.log" || fail 'cannot list peer snapshots'
id=$(python3 - "$work/snapshots.json" "$source_host" <<'PY'
import json, re, sys
items = json.load(open(sys.argv[1]))
assert len(items) == 1 and items[0]['hostname'] == sys.argv[2], 'need exactly one snapshot of the requested host'
sid = items[0]['id']
assert re.fullmatch('[a-f0-9]{64}', sid), 'invalid snapshot metadata'
print(sid)
PY
)
args=()
for path in "${includes[@]}"; do args+=(--include "$path"); done
restic-peer --no-cache --no-lock restore "$id" --verify --target "$work/restored" "${args[@]}" >"$work/restore.log" 2>&1 || fail 'peer restore/verification failed'
if [[ "$role" == laptop ]]; then
  test -d "$work/restored/home/vino/Documents" || fail 'Documents missing from laptop snapshot'
  count=$(find "$work/restored/home/vino/Documents" -type f | wc -l)
  (( count > 0 )) || fail 'no restored laptop files'
  echo "PASS laptop snapshot=$id Documents files=$count (restic content verification)"
  exit
fi

stage=$work/restored/var/backup/restic-staging-peer
pgdump=$work/restored/var/backup/postgresql/all.sql.gz
test -f "$stage/aiia/mysql.sql.gz" && test -f "$pgdump" || fail 'database dumps missing'
test -d "$work/restored/srv/containers/aiia/content-data" || fail 'Ghost content-data missing'
# A restored symlink must not turn a scratch check into a read of a live path.
test -z "$(find "$work/restored" -type l -print -quit)" || fail 'lab restore contains a symlink; review it before testing'
python3 - "$stage/vaultwarden/db.sqlite3" "$stage/mrija/mail_index.sqlite" <<'PY'
import pathlib, sqlite3, sys
for filename in sys.argv[1:]:
    p = pathlib.Path(filename)
    assert p.is_file(), 'required SQLite snapshot missing'
    with sqlite3.connect(p.as_uri() + '?mode=ro', uri=True) as db:
        assert db.execute('PRAGMA integrity_check').fetchall() == [('ok',)], 'SQLite integrity failure'
        assert db.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0] > 0, 'empty SQLite schema'
        if p.name == 'db.sqlite3':
            users = db.execute('SELECT count(*) FROM users').fetchone()[0]
            assert users > 0, 'Vaultwarden snapshot has no users'
            print(f'PASS Vaultwarden users={users}')
print('PASS Vaultwarden and Mrija SQLite integrity/schema')
PY

mysql_image=mysql:8.4@sha256:b3b90af2a6552ae30c266fdb7d5dd55f3afb72404bb78d37fe8a23eb857fd3fb
pg_image=${PG_IMAGE:?set PG_IMAGE to a locally loaded postgres:16 image pinned by digest}
[[ "$pg_image" =~ ^postgres:16@sha256:[a-f0-9]{64}$ ]] || fail 'PG_IMAGE must be postgres:16 pinned by digest'
mc_image=itzg/minecraft-server@sha256:769a826c340586e9d483a0eb6437b8e2c3611aea6a115ff072a2fe372d43e2be
for image in "$mysql_image" "$pg_image" "$mc_image"; do docker image inspect "$image" >/dev/null 2>&1 || fail 'required drill image not loaded'; done
mysql=$prefix-mysql
pg=$prefix-postgres
pg_admin=$prefix-admin
mc=$prefix-minecraft
containers+=("$mysql")
docker run -d --pull never --name "$mysql" --network none --memory 2g --cpus 2 --security-opt no-new-privileges \
  --tmpfs /var/lib/mysql:rw -e MYSQL_ALLOW_EMPTY_PASSWORD=yes "$mysql_image" >"$work/mysql-start.log" 2>&1 || fail 'temporary MySQL startup failed'
ready=false
for _ in $(seq 1 90); do
  if docker exec "$mysql" mysqladmin ping -uroot --silent >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
[[ "$ready" == true ]] || fail 'temporary MySQL not ready'
# --all-databases may restore root's password; verify in the same authenticated session.
(
  gzip -dc "$stage/aiia/mysql.sql.gz" || exit 1
  printf "\nSELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('mysql','sys','performance_schema','information_schema');\n"
) | docker exec -i "$mysql" mysql -uroot -N >"$work/mysql-import.log" 2>"$work/mysql-error.log" || fail 'MySQL dump import failed'
tables=$(tail -n 1 "$work/mysql-import.log")
[[ "$tables" =~ ^[0-9]+$ ]] || fail 'invalid MySQL table count'
(( tables > 0 )) || fail 'MySQL import has no application tables'
echo "PASS MySQL import application tables=$tables"

containers+=("$pg")
docker run -d --pull never --name "$pg" --network none --memory 2g --cpus 2 --security-opt no-new-privileges \
  --tmpfs /var/lib/postgresql/data:rw -e POSTGRES_HOST_AUTH_METHOD=trust -e "POSTGRES_USER=$pg_admin" \
  -e POSTGRES_DB=restore_drill_bootstrap "$pg_image" >"$work/pg-start.log" 2>&1 || fail 'temporary PostgreSQL startup failed'
ready=false
for _ in $(seq 1 60); do
  if docker exec "$pg" pg_isready -U "$pg_admin" -d postgres >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
[[ "$ready" == true ]] || fail 'temporary PostgreSQL not ready'
gzip -dc "$pgdump" | docker exec -i "$pg" psql -U "$pg_admin" -d postgres -v ON_ERROR_STOP=1 >"$work/pg-import.log" 2>&1 || fail 'PostgreSQL dump import failed'
databases=$(docker exec "$pg" psql -U "$pg_admin" -d postgres -Atc "SELECT count(*) FROM pg_database WHERE NOT datistemplate AND datname NOT IN ('postgres','restore_drill_bootstrap');")
[[ "$databases" =~ ^[0-9]+$ ]] || fail 'invalid PostgreSQL database count'
(( databases > 0 )) || fail 'PostgreSQL import has no application database'
echo "PASS PostgreSQL import application databases=$databases"

world=$stage/minecraft
test -f "$world/server.properties" || fail 'Minecraft snapshot missing'
test -n "$(find "$world/world" -name '*.mca' -type f -print -quit)" || fail 'Minecraft region files missing'
shopt -s nullglob
jars=("$world"/paper-*.jar)
(( ${#jars[@]} == 1 )) || fail 'need exactly one backed-up Paper jar'
# Plugins may hold external service credentials; this tests the world, not plugin integrations.
if [[ -d "$world/plugins" ]]; then mv "$world/plugins" "$world/plugins.disabled"; fi
containers+=("$mc")
docker run -d --pull never --name "$mc" --network bridge --memory 4g --cpus 2 --security-opt no-new-privileges \
  -e EULA=TRUE -e TYPE=CUSTOM -e "CUSTOM_SERVER=/data/$(basename "${jars[0]}")" -e MEMORY=2G \
  -e ENABLE_RCON=false -e CREATE_CONSOLE_IN_PIPE=true -e ONLINE_MODE=false \
  -v "$world:/data" "$mc_image" >"$work/mc-start.log" 2>&1 || fail 'temporary Minecraft startup failed'
ready=false
for _ in $(seq 1 90); do
  docker logs "$mc" >"$work/mc.log" 2>&1 || fail 'cannot read temporary Minecraft logs'
  if grep -q 'Done (' "$work/mc.log"; then ready=true; break; fi
  [[ $(docker inspect --format '{{.State.Running}}' "$mc") == true ]] || fail 'temporary Minecraft exited'
  sleep 3
done
[[ "$ready" == true ]] || fail 'temporary Minecraft boot timed out'
if grep -qE 'ERROR\]|FATAL\]' "$work/mc.log"; then fail 'Minecraft startup logged errors'; fi
docker stop "$mc" >/dev/null || fail 'temporary Minecraft stop failed'
echo "PASS lab snapshot=$id SQLite, MySQL, PostgreSQL, Minecraft world boot; plugins disabled"
