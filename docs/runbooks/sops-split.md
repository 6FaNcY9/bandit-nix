# Splitting `secrets/secrets.yaml` per host

One-time migration so a compromised or stolen host cannot decrypt the other
host's secrets. Target layout:

| File | Recipients | Consumed by |
| --- | --- | --- |
| `secrets/bandit.yaml` | `user` + `host_bandit` | laptop (`nixos/secrets-workstation.nix`) |
| `secrets/github.yaml` | `user` + `host_bandit` | laptop |
| `secrets/lab.yaml` | `user` + `host_bandit_lab` | bandit-lab (`nixos/server/default.nix` default file) |
| `secrets/secrets.yaml` | all three | **legacy, deleted in the cleanup step** |

`.sops.yaml` rules are ordered: `lab.yaml`, `bandit|github.yaml`, the temporary
legacy rule, then a catch-all that encrypts to `user` only (a stray new file
fails safe).

**Why a fresh data key matters.** `sops updatekeys` only re-wraps the existing
data key. A host that held the old file would still be able to decrypt a copy
that merely lost its recipient. Every new file therefore gets `sops rotate -i`,
which generates a new data key and re-encrypts all values.

**What this does not fix.** Old `secrets.yaml` commits stay readable by all
three keys forever, and bandit-lab has held the laptop's secrets in plaintext.
Isolation only covers values created or rotated after the split; rotate the
exposed values (`secret-rotation.md`, "Exposed on bandit-lab").

Nothing here touches host age keys or `/var/lib/sops-nix/key.txt`. Old system
generations reference their own store copy of `secrets.yaml`, so rollback keeps
working.

## 1. Create the new files (laptop, you; agents must not decrypt)

Work from a clean checkout on the laptop. Key *names* are cleartext in sops
files, so the loop below needs no decryption to decide what to remove.

```bash
cd ~/src/bandit-nix
cp -a secrets ~/secrets-backup-$(date +%Y%m%d)   # encrypted copies, for rollback

KEEP_LAB="user-password thehost-sshkey cloudflare-tunnel-credentials vaultwarden-admin-token grafana-admin-password mrija-api-key mrija-password aiia-fal-key aiia-gelato-api-key aiia-stripe-secret-key aiia-stripe-publishable-key aiia-stripe-webhook-secret aiia-mysql-password aiia-mysql-root-password wazuh-admin-password wazuh-api-password wazuh-dashboard-password wazuh-internal-users-yml wazuh-tls-admin-key wazuh-tls-indexer-key wazuh-tls-manager-key wazuh-tls-dashboard-key wazuh-tls-root-ca-key wazuh-tls-root-ca-manager-key crowdsec-firewall-bouncer-key crowdsec-traefik-bouncer-key"
KEEP_BANDIT="user-password thehost-sshkey cachix-secret context7_api_key firecrawl-api-key shodan-api-key cloudflare-api-key digitalOcean-sshkey tokenrouter-api-key"

mk() {
  local f=$1; shift; local keep=" $* "
  cp secrets/secrets.yaml "secrets/$f.yaml"
  for k in $(grep -E '^[A-Za-z0-9_-]+:' "secrets/$f.yaml" | cut -d: -f1 | grep -vx sops); do
    case "$keep" in *" $k "*) ;; *) sops unset "secrets/$f.yaml" "[\"$k\"]" ;; esac
  done
  sops updatekeys -y "secrets/$f.yaml"
  sops rotate -i "secrets/$f.yaml"
}
mk lab $KEEP_LAB
mk bandit $KEEP_BANDIT

# Show what each file now holds (names only) and compare to the keep lists:
for f in lab bandit; do echo "$f: $(grep -E '^[A-Za-z0-9_-]+:' secrets/$f.yaml | cut -d: -f1 | grep -vx sops | tr '\n' ' ')"; done
```

`secrets.yaml` stays untouched. `thehost-sshkey` is deliberately in both files:
the laptop uses it as an SSH identity and the lab's Mrija archive container
mounts it. Both copies start with the same value; replace them with separate
keypairs afterwards (`secret-rotation.md`).

Give the lab its own login-password hash (it currently shares the laptop's):

```bash
mkpasswd -m yescrypt | tr -d '\n' | jq -Rs . | sops set --value-stdin secrets/lab.yaml '["user-password"]'
```

You will be prompted for the new password. Remember it before activating: the
lab accounts are `mutableUsers = false`, so this hash *is* the login password
after the next activation.

## 2. Verify isolation without printing anything

Each host key must decrypt only its own file:

```bash
# laptop key must FAIL on lab.yaml, SUCCEED on bandit.yaml
sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops -d secrets/lab.yaml >/dev/null; echo "lab.yaml: exit $? (want non-zero)"
sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops -d --extract '["user-password"]' secrets/bandit.yaml >/dev/null; echo "bandit.yaml: exit $? (want 0)"

```

Mirror image on the lab: copy the (encrypted) files over, then run on the lab:

```bash
# laptop
scp secrets/bandit.yaml secrets/lab.yaml bandit-lab:/tmp/

# lab
sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt nix shell nixpkgs#sops --command sops -d /tmp/bandit.yaml >/dev/null; echo "bandit.yaml: exit $? (want non-zero)"
sudo env SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt nix shell nixpkgs#sops --command sops -d --extract '["user-password"]' /tmp/lab.yaml >/dev/null; echo "lab.yaml: exit $? (want 0)"
rm /tmp/bandit.yaml /tmp/lab.yaml
```

Then commit the data (this is "Commit A": no behaviour change yet):

```bash
git add .sops.yaml secrets/lab.yaml secrets/bandit.yaml
git commit -S -m "security(sops): split secrets per host (data only)"
```

## 3. Module change (agent-prepared, "Commit B")

Switches the hosts to their own files and adds the `sops-isolation` flake
check. Before it can activate anywhere:

- each host must be able to decrypt `user-password` from its new file
  (otherwise the account password is locked), which step 2 proves;
- every secret a host declares must exist as a top-level key in that host's
  file (the check asserts this; `bandit-ci` disables sops validation, so build
  the real toplevels).

Activate by hand, never through the paused updater:

- Laptop: `nixos-rebuild test` with a root shell open; check
  `/run/secrets-for-users/user-password` exists and `sudo -k; sudo true` works;
  then `switch`.
- Lab: activate with an SSH session kept open, then `bandit-lab-health`, check
  the vaultwarden, mrija and wazuh containers and `ls /run/secrets/rendered`.
  The lab stops receiving the laptop-only secrets; stale links under
  `~vino/.ssh` (`github*`) can be removed by hand.

## 4. Cleanup (only after both hosts run Commit B)

```bash
git rm secrets/secrets.yaml
# remove the TEMPORARY legacy rule from .sops.yaml and the legacy entry in the
# sops-isolation check, then:
sops updatekeys -y secrets/github.yaml && sops rotate -i secrets/github.yaml
```

`github.yaml` still lists the lab key until this step; do **not** run it
earlier or while the lab configuration still references that file. Then rotate
the values listed in `secret-rotation.md` and only afterwards decide whether to
unpause `lab-update`.
