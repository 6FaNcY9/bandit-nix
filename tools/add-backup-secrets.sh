#!/usr/bin/env bash
# One-time operator helper for docs/runbooks/backup-restore.md.
# Adds the four restic/Spaces secrets to secrets/lab.yaml. Values are typed at hidden
# prompts (or generated) and go straight into sops; nothing is printed or stored
# anywhere else. Run it yourself in a normal terminal.
set -euo pipefail
cd "$(dirname "$0")/.."
f=secrets/lab.yaml
[[ -f $f ]] || { echo "$f not found (run from the repository)" >&2; exit 1; }
have() { grep -qE "^$1:" "$f"; }
put() { printf '%s' "$2" | jq -Rs . | sops set --value-stdin "$f" "[\"$1\"]"; }

for k in restic-repository restic-password restic-s3-access-key-id restic-s3-secret-access-key; do
  if have "$k"; then echo "$k already exists in $f; refusing to overwrite (edit it with 'sops $f')" >&2; exit 1; fi
done

read -r -p "Spaces region (e.g. fra1): " region
[[ $region =~ ^[a-z]{3}[0-9]$ ]] || { echo "unexpected region" >&2; exit 1; }
read -r -p "Space (bucket) name (e.g. bandit-lab-backup): " bucket
[[ $bucket =~ ^[a-z0-9][a-z0-9-]{2,62}$ ]] || { echo "unexpected bucket name" >&2; exit 1; }
put restic-repository "s3:https://${region}.digitaloceanspaces.com/${bucket}/restic"

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

read -r -s -p "Spaces access key ID: " id; echo; put restic-s3-access-key-id "$id"
read -r -s -p "Spaces secret key: " key; echo; put restic-s3-secret-access-key "$key"
echo "Added 4 secrets to $f. Next: set bandit-lab.backups.enable = true (runbook step 4)."
