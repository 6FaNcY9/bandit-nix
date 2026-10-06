#!/usr/bin/env bash
# One-time operator helper for docs/runbooks/backup-restore.md.
# Adds the four restic/B2 secrets to secrets/lab.yaml. Values are typed at hidden
# prompts (or generated) and go straight into sops; nothing is printed or stored
# anywhere else. Run it yourself in a normal terminal.
set -euo pipefail
cd "$(dirname "$0")/.."
f=secrets/lab.yaml
[[ -f $f ]] || { echo "$f not found (run from the repository)" >&2; exit 1; }
have() { grep -qE "^$1:" "$f"; }
put() { printf '%s' "$2" | jq -Rs . | sops set --value-stdin "$f" "[\"$1\"]"; }

for k in restic-repository restic-password restic-b2-account-id restic-b2-account-key; do
  if have "$k"; then echo "$k already exists in $f; refusing to overwrite (edit it with 'sops $f')" >&2; exit 1; fi
done

read -r -p "B2 bucket name (e.g. bandit-lab-backup): " bucket
[[ $bucket =~ ^[A-Za-z0-9-]{6,}$ ]] || { echo "unexpected bucket name" >&2; exit 1; }
put restic-repository "b2:${bucket}:/"

read -r -p "Generate the restic repository password now? [Y/n] " gen
if [[ ${gen:-Y} =~ ^[Yy]$ ]]; then
  pw=$(openssl rand -base64 48 | tr -d '\n')
  put restic-password "$pw"
  echo
  echo "=== SAVE THIS PASSWORD OFFLINE NOW (password manager on another device, or paper) ==="
  echo "$pw"
  echo "Without it every backup is unreadable. It is not shown again."
  read -r -p "Press Enter once you have stored it safely... " _
  clear 2>/dev/null || true
else
  read -r -s -p "restic password: " pw; echo; put restic-password "$pw"
fi

read -r -s -p "B2 application keyID: " id; echo; put restic-b2-account-id "$id"
read -r -s -p "B2 applicationKey: " key; echo; put restic-b2-account-key "$key"
echo "Added 4 secrets to $f. Next: set bandit-lab.backups.enable = true (runbook step 4)."
