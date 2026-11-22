# pre-receive hook of the aiia deploy repository (deploy.nix): only deploy/bandit-lab may be
# pushed. Deletes and non-fast-forward pushes are refused by the repository's git config.
ok=1
while read -r _old new ref; do
  if [ "$ref" != refs/heads/deploy/bandit-lab ]; then
    echo "refused $ref: only deploy/bandit-lab can be pushed here" >&2
    ok=0
  elif [[ $new =~ ^0+$ ]]; then
    echo "refused: deploy/bandit-lab cannot be deleted" >&2
    ok=0
  fi
done
[ "$ok" = 1 ] || exit 1
echo "accepted. To go live: ssh aiia-lab deploy" >&2
