#!/usr/bin/env bash
# One-time owner helper for docs/runbooks/backup-peer.md.
#   tools/backup-peer-secrets.sh secrets   # BEFORE deploying: writes 8 sops keys
#   tools/backup-peer-secrets.sh init      # AFTER both hosts run: restic init x2
# Generated values never reach stdout, the process list or the Nix store; the
# four passwords are derived into every file that needs them in ONE run, so
# URL, htpasswd hash and repository password cannot drift apart.
set -euo pipefail
cd "$(dirname "$0")/.."
# openssl, htpasswd and restic are not installed system-wide: re-run inside nix shell.
if [[ -z ${BACKUP_PEER_SHELL:-} ]]; then
  BACKUP_PEER_SHELL=1 exec nix shell nixpkgs#openssl nixpkgs#apacheHttpd nixpkgs#restic -c bash "$0" "$@"
fi
lab_ip=100.125.161.81 laptop_ip=100.102.247.30 port=8000
lab=secrets/lab.yaml bandit=secrets/bandit.yaml
keys=(restic-peer-repository restic-peer-password restic-peer-htpasswd restic-peer-prune-password)

put() { printf '%s' "$3" | jq -Rs . | sops set --value-stdin "$1" "[\"$2\"]"; }
get() { sops decrypt --extract "[\"$2\"]" "$1"; }
# bcrypt htpasswd line; the password goes in on stdin (-i), not on a command line.
htp() { printf '%s' "$2" | htpasswd -niB "$1"; }
gen() { openssl rand -hex 32 | tr -d '\n'; }

case ${1:-} in
secrets)
  for f in "$lab" "$bandit"; do for k in "${keys[@]}"; do
    ! grep -qE "^$k:" "$f" || { echo "$k already in $f; refusing to overwrite" >&2; exit 1; }
  done; done
  lab_srv_pw=$(gen)      # user "lab"    on the laptop's REST server
  bandit_srv_pw=$(gen)   # user "bandit" on the lab's REST server
  lab_repo_pw=$(gen)     # encrypts the lab's repo (stored on the laptop)
  bandit_repo_pw=$(gen)  # encrypts the laptop's repo (stored on the lab)
  # bandit.yaml (laptop)
  put "$bandit" restic-peer-repository "rest:http://bandit:${bandit_srv_pw}@${lab_ip}:${port}/bandit/"
  put "$bandit" restic-peer-password "$bandit_repo_pw"
  put "$bandit" restic-peer-htpasswd "$(htp lab "$lab_srv_pw")"
  put "$bandit" restic-peer-prune-password "$lab_repo_pw"
  # lab.yaml (bandit-lab)
  put "$lab" restic-peer-repository "rest:http://lab:${lab_srv_pw}@${laptop_ip}:${port}/lab/"
  put "$lab" restic-peer-password "$lab_repo_pw"
  put "$lab" restic-peer-htpasswd "$(htp bandit "$bandit_srv_pw")"
  put "$lab" restic-peer-prune-password "$bandit_repo_pw"
  echo "8 keys written. Back up your sops age key offline: it is the only way to read the repository passwords."
  ;;
init)
  # Each repo is initialised with the client's own URL/password, from this laptop.
  RESTIC_REPOSITORY=$(get "$bandit" restic-peer-repository) RESTIC_PASSWORD=$(get "$bandit" restic-peer-password) restic init
  RESTIC_REPOSITORY=$(get "$lab" restic-peer-repository) RESTIC_PASSWORD=$(get "$lab" restic-peer-password) restic init
  ;;
*) echo "usage: $0 secrets|init" >&2; exit 2 ;;
esac
