# Jerry guest box

## What it is

A systemd-nspawn NixOS container (`containers.jerry`) on bandit-lab plus an
append-only restic repository for a friend (Jerry). Pinned user namespace
(base 524288), 1 CPU, 2 GB RAM, 50 GB `/data`, own tailnet node `tag:jerry-box`,
NATed out, refused by the host and walled off from LAN, bots and Docker. The
kernel is shared (accepted, see `docs/SECURITY-PLAN.md` A6). Design:
`docs/superpowers/specs/2026-11-01-jerry-guest-box-design.md`. Files:
`hosts/bandit-lab/services/jerry-box/` (`default.nix`, `watch.nix`, `report.sh`,
`watch.sh`) and `hosts/bandit-lab/services/backup/peer.nix`.

## Owner setup, in order

1. **Tailscale admin console.** Invite Jerry, then add to the policy file
   (`<jerry@example.com>` is his login):

   ```json
   "tagOwners": {"tag:jerry-box": ["autogroup:admin"]},
   "grants": [
     {"src": ["<jerry@example.com>"], "dst": ["tag:jerry-box"], "ip": ["tcp:22"]},
     {"src": ["<jerry@example.com>", "tag:jerry-box"], "dst": ["100.125.161.81"], "ip": ["tcp:8000"]}
   ]
   ```

   (Equivalent `acls` entries: `<jerry@example.com> -> tag:jerry-box:22` and
   `<jerry@example.com>, tag:jerry-box -> 100.125.161.81:8000`.)
2. **Auth key.** Settings, Keys, Generate auth key: reusable off, ephemeral off,
   pre-authorized on, tag `tag:jerry-box`, 90-day expiry (used once).
3. **Secrets**, on the laptop from the repo root: `sops secrets/lab.yaml`. Add
   `jerry-tailscale-authkey` (the key from step 2), `restic-peer-prune-password-jerry`
   (new random passphrase) and append Jerry's htpasswd line to
   `restic-peer-htpasswd` (`nix shell nixpkgs#apacheHttpd -c htpasswd -nB jerry`).
4. **SSH key.** Paste Jerry's public key (collected out of band) into `jerryKey`
   in `hosts/bandit-lab/services/jerry-box/default.nix`, commit.
5. **Subvolumes**, as root on the lab. The restic part is in
   [backup-peer.md, "Extra peer: jerry"](backup-peer.md#extra-peer-jerry); do not
   repeat it here. Additionally the box:

   ```bash
   btrfs subvolume create /srv/jerry/box && btrfs qgroup limit 50G /srv/jerry/box
   ```

   If a subvolume was created after the mount unit had already failed:

   ```bash
   systemctl restart 'srv-backup-restic\x2dpeer-jerry.mount'
   systemctl start restic-rest-server.socket
   ```
6. **Apply**: `lab-apply` from the laptop (or push to `main` and wait for the
   hourly timer).
7. **Tailnet IP.** Read the container's address:
   `ssh bandit-lab 'sudo nixos-container run jerry -- tailscale ip -4'`. Put
   Jerry's device IPs (the container's included, for backups from the box) into
   `extraPeers.jerry.ips` in `hosts/bandit-lab/services/backup/peer.nix`,
   commit, apply again. Until then nothing is admitted to port 8000.

## Checks

On the lab:

```bash
systemctl status container@jerry auditd jerry-ssh-watch jerry-restic-watch jerry-report.timer
ausearch -k jerry | tail
btrfs qgroup show -reF /srv/jerry/restic
iptables -S DOCKER-USER | grep ve-jerry                        # three DROP rules
ls -ln /var/lib/nixos-containers/jerry/var/lib/tailscale/      # authkey owned by 524288
journalctl -M jerry -u sshd -n 5                               # host can read the container journal
systemctl status jerry-report.timer
```

## Pause / remove

Pause: `systemctl stop container@jerry`. Remove: delete the Tailscale ACL rules
and the `tag:jerry-box` node, `nixos-container destroy jerry`,
`btrfs subvolume delete /srv/jerry/box /srv/jerry/restic`, drop the three jerry
secrets from `secrets/lab.yaml`, remove the config from the repo.

## Handover to Jerry

Technical note, he knows the field.

- SSH: `ssh root@<container tailnet name>` (key only; tailnet ACL allows your login to port 22).
- Limits: 1 CPU, 2 GB RAM without swap (an OOM kill is yours to handle), 512
  tasks. `/data` is 50 GB; put models and data there. The rest of the root
  filesystem is not quota-counted but is not backed up either. Egress is NAT
  with DNS 9.9.9.9/1.1.1.1; no LAN, no other tailnet nodes.
- Backup: `rest:http://jerry:<pw>@100.125.161.81:8000/jerry/` with your own
  restic password. The repo is append-only, 512 GB quota; you cannot forget or
  prune. Retention is applied on the host: keep-daily 7, keep-weekly 5,
  keep-monthly 12.
- Visibility: the owner receives an hourly report of the box's processes (names,
  exit codes and counts; no arguments) and an immediate notice on every SSH
  login and every backup session. Treat process names and logins as visible.
- The owner does not support software inside the container.
