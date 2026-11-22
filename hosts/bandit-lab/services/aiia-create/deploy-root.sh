# aiia-deploy-root: the root half of Albert's direct deploy (deploy.nix). Runs only as one of
# the fixed units aiia-deploy-install, aiia-deploy-rollback, aiia-deploy-logs@{api,web}, which
# the user aiia-deploy may start (polkit) but not change. Test: deploy-root.test.sh.
#   install   copy out/{api,web}.tar with aiia-deploy's rights into a root-only directory, load
#             them under the units' image names (the archives' own tags are ignored), save +
#             copy Redis, start, check; on a failed check or error the old images go back
#   rollback  swap the running images with the ones that ran before; Redis is not touched
#   logs X    the last 300 journal lines of aiia-create-X
in=${AIIA_DEPLOY_IN:-/srv/aiia-deploy/out}
st=${AIIA_DEPLOY_STATE:-/var/lib/aiia-deploy}
work=${AIIA_DEPLOY_WORK:-/var/lib/aiia-deploy-root}
data=${AIIA_REDIS_PARENT:-/srv/containers/aiia-create}
group=${AIIA_DEPLOY_GROUP:-aiia-deploy}
# read the user's files as the user: no symlink, hardlink or FIFO there can make root read more
read -ra read_as <<<"${AIIA_READ_AS:-setpriv --reuid=aiia-deploy --regid=aiia-deploy --clear-groups --reset-env}"
max=${AIIA_MAX_ARCHIVE:-4294967296} # 4 GiB per image archive (root's image store is outside the qgroup)
tries=${AIIA_CHECK_TRIES:-30}
pause=${AIIA_CHECK_SLEEP:-3}
keep=${AIIA_KEEP_SNAPSHOTS:-10}
API=ghcr.io/6fancy9/aiia-generator-api
WEB=ghcr.io/6fancy9/aiia-generator-web
units=(aiia-create-api aiia-create-web)
sha="" old_api="" old_web="" old_prev_api="" old_prev_web="" new_api="" new_web=""

notify() { # title, body: one push to vino's phone (same ntfy topic as the lab alerts)
  [ -n "${NTFY_TOKEN:-}" ] || return 0
  curl -fsS -m 10 -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: $1" -d "$2" "$NTFY_URL/$NTFY_TOPIC" >/dev/null || true
}

id_of() { podman image inspect --format '{{.Id}}' "$1" 2>/dev/null || true; }

rev_of() { # the commit an image was built from, or "unknown" (images built on the laptop have no label)
  local r
  r=$(podman image inspect --format '{{index .Labels "org.opencontainers.image.revision"}}' "$1" 2>/dev/null || true)
  if [[ $r =~ ^[0-9a-f]{40}$ ]]; then echo "$r"; else echo unknown; fi
}

set_tag() { # image id or "", name: point name at the id, or remove the name when the id is empty
  if [ -n "$1" ]; then
    podman tag "$1" "$2"
  elif [ -n "$(id_of "$2")" ]; then
    podman untag "$2" "$2"
  fi
}

drop_image() { # id: remove an image of ours that no name points to any more (never with force)
  [ -n "$1" ] || return 0
  case " $(id_of "$API:main") $(id_of "$API:prev") $(id_of "$WEB:main") $(id_of "$WEB:prev") " in
  *" $1 "*) return 0 ;;
  esac
  podman rmi "$1" >/dev/null 2>&1 || true
}

check() { # both units active, /healthz 200, /api/session 200 through Traefik, and still active a bit later
  local i a=- w=- h=- s=-
  for ((i = 1; i <= tries; i++)); do
    sleep "$pause"
    a=$(systemctl is-active aiia-create-api || true)
    w=$(systemctl is-active aiia-create-web || true)
    h=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1:3080/healthz || true)
    s=$(curl -s -o /dev/null -m 5 -w '%{http_code}' -H 'Host: aiia.at' http://127.0.0.1/api/session || true)
    if [ "$a $w $h $s" = "active active 200 200" ]; then
      sleep "$((pause * 3))"
      a=$(systemctl is-active aiia-create-api || true)
      w=$(systemctl is-active aiia-create-web || true)
      if [ "$a $w" = "active active" ]; then
        echo "check ok: api $a, web $w, healthz $h, session $s"
        return 0
      fi
    fi
  done
  echo "check FAILED: api $a, web $w, healthz $h, session $s"
  return 1
}

restart() {
  systemctl reset-failed "${units[@]}" 2>/dev/null || true
  systemctl restart "${units[@]}"
}

record() { # state file for "status", one line per run in deploys.log (with the image ids)
  printf 'deployed: %s (%s)\nprevious: %s\n' "$(rev_of "$API:main")" "$(date -Is)" "$(rev_of "$API:prev")" >"$st/state.new"
  chgrp "$group" "$st/state.new"
  chmod 0640 "$st/state.new"
  mv "$st/state.new" "$st/state"
  printf '%s %s api=%.12s web=%.12s\n' "$(date -Is)" "$1" "$(id_of "$API:main")" "$(id_of "$WEB:main")" >>"$st/deploys.log"
}

back_to_old() { # after a failed check, or any error once the site is being stopped
  trap - ERR
  set +e
  if [ -z "$old_api" ] || [ -z "$old_web" ]; then
    record "${sha:0:7} failed-no-previous"
    notify "aiia deploy FAILED" "${sha:0:7} failed and there is no previous image: the site may be down"
    echo "FAILED and there was no previous version to go back to. vino is notified."
    exit 1
  fi
  echo "going back to the previous images ..."
  podman tag "$old_api" "$API:main"
  podman tag "$old_web" "$WEB:main"
  set_tag "$old_prev_api" "$API:prev"
  set_tag "$old_prev_web" "$WEB:prev"
  if restart && check; then
    drop_image "$new_api"
    drop_image "$new_web"
    record "${sha:0:7} rolled-back"
    notify "aiia deploy rolled back" "${sha:0:7} failed; the previous version runs again"
    echo "ROLLED BACK: ${sha:0:7} failed, the previous version runs again. Look at: ssh aiia-lab logs api"
  else
    record "${sha:0:7} rollback-failed"
    notify "aiia DOWN after deploy" "${sha:0:7} failed and going back failed too: needs vino"
    echo "FAILED, and going back failed too. vino is notified."
  fi
  exit 1
}

fetch() { # name, size limit: copy one file from the user's out/ into the root-only work dir
  local n
  # absolute path: setpriv --reset-env sets a PATH that does not exist on NixOS
  timeout 300 "${read_as[@]}" "$(command -v head)" -c "$(($2 + 1))" "$in/$1" >"$work/$1" || {
    echo "cannot read $1"
    exit 1
  }
  n=$(stat -c %s "$work/$1")
  if [ "$n" -gt "$2" ] || [ "$n" -eq 0 ]; then
    echo "refused $1: $n bytes (limit $2)"
    exit 1
  fi
}

install_images() {
  local snap
  rm -f "$work"/api.tar "$work"/web.tar "$work"/sha
  fetch sha 64
  sha=$(tr -d '\n' <"$work/sha")
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || {
    echo "no valid commit in out/sha"
    exit 1
  }
  fetch api.tar "$max"
  fetch web.tar "$max"
  # a :new left by an earlier failed load would otherwise stay in root's store for good
  drop_image "$(id_of "$API:new")"
  drop_image "$(id_of "$WEB:new")"
  echo "loading ${sha:0:7} ..."
  skopeo copy -q "docker-archive:$work/api.tar" "containers-storage:$API:new"
  skopeo copy -q "docker-archive:$work/web.tar" "containers-storage:$WEB:new"
  rm -f "$work"/api.tar "$work"/web.tar
  new_api=$(id_of "$API:new")
  new_web=$(id_of "$WEB:new")
  old_api=$(id_of "$API:main")
  old_web=$(id_of "$WEB:main")
  old_prev_api=$(id_of "$API:prev")
  old_prev_web=$(id_of "$WEB:prev")

  # from here on any unexpected error puts the old images back and starts them
  trap back_to_old ERR
  echo "stopping the site, saving Redis ..."
  systemctl stop aiia-create-web aiia-create-api
  snap=$data/redis-deploy-$(date +%Y%m%d-%H%M%S)-${sha:0:7}
  if ! podman exec aiia-create-redis redis-cli SAVE || ! cp -a --reflink=auto "$data/redis" "$snap"; then
    trap - ERR
    echo "Redis snapshot FAILED: starting the old version again, nothing deployed"
    podman untag "$API:new" "$API:new" || true
    podman untag "$WEB:new" "$WEB:new" || true
    drop_image "$new_api"
    drop_image "$new_web"
    restart || true
    notify "aiia deploy failed" "${sha:0:7}: Redis snapshot failed, old version started again"
    record "${sha:0:7} snapshot-failed"
    exit 1
  fi
  echo "Redis saved as $snap"
  set_tag "$old_api" "$API:prev"
  set_tag "$old_web" "$WEB:prev"
  podman tag "$new_api" "$API:main"
  podman tag "$new_web" "$WEB:main"
  podman untag "$API:new" "$API:new"
  podman untag "$WEB:new" "$WEB:new"
  echo "starting ${sha:0:7} ..."
  if restart && check; then
    trap - ERR
    find "$data" -maxdepth 1 -name 'redis-deploy-*' -printf '%f\n' | sort | head -n "-$keep" | while read -r d; do rm -rf "${data:?}/$d" || true; done
    drop_image "$old_prev_api"
    drop_image "$old_prev_web"
    record "${sha:0:7} ok"
    notify "aiia deployed ${sha:0:7}" "Albert's deploy is live and the check passed"
    echo "LIVE: ${sha:0:7}"
    return 0
  fi
  back_to_old
}

rollback() {
  local cur_api cur_web prev_api prev_web
  prev_api=$(id_of "$API:prev")
  prev_web=$(id_of "$WEB:prev")
  if [ -z "$prev_api" ] || [ -z "$prev_web" ]; then
    echo "there is no previous version to go back to"
    exit 1
  fi
  cur_api=$(id_of "$API:main")
  cur_web=$(id_of "$WEB:main")
  podman tag "$prev_api" "$API:main"
  podman tag "$prev_web" "$WEB:main"
  set_tag "$cur_api" "$API:prev"
  set_tag "$cur_web" "$WEB:prev"
  echo "starting the previous version (Redis data stays as it is) ..."
  if restart && check; then
    record "rollback ok"
    notify "aiia rolled back" "Albert went back to the previous version; it runs and the check passed"
    echo "BACK: the previous version runs. A second rollback goes forward again."
    return 0
  fi
  echo "the previous version does not pass the check: starting the one that ran before the rollback ..."
  set_tag "$cur_api" "$API:main"
  set_tag "$cur_web" "$WEB:main"
  podman tag "$prev_api" "$API:prev"
  podman tag "$prev_web" "$WEB:prev"
  if restart && check; then
    record "rollback failed-check, kept current"
    notify "aiia rollback refused" "the previous version failed its check; the current one runs again"
    echo "NOT ROLLED BACK: the previous version failed its check, the current one runs again."
  else
    record "rollback failed-check, current failed too"
    notify "aiia DOWN after rollback" "neither version passes the check: needs vino"
    echo "FAILED: neither version passes the check. vino is notified."
  fi
  exit 1
}

logged() { # file, command...: output to a file aiia-deploy may read, and to the journal
  local f=$1
  shift
  install -m 0640 -g "$group" /dev/null "$f"
  "$@" 2>&1 | tee "$f"
}

exec 8>"${AIIA_DEPLOY_LOCK:-/run/aiia-deploy-root.lock}"
flock -n 8 || {
  echo "another deploy step is running"
  exit 1
}
set -E
case "${1:-} ${2:-}" in
"install ") logged "$st/install.log" install_images ;;
"rollback ") logged "$st/rollback.log" rollback ;;
"logs api" | "logs web")
  install -m 0640 -g "$group" /dev/null "$st/logs-$2.txt.new"
  journalctl -u "aiia-create-$2" -n 300 --no-pager -o short-iso >"$st/logs-$2.txt.new" 2>&1 || true
  mv "$st/logs-$2.txt.new" "$st/logs-$2.txt"
  ;;
*)
  echo "usage: aiia-deploy-root install|rollback|logs api|web" >&2
  exit 2
  ;;
esac
