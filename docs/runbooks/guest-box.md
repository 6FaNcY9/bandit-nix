# Guest boxes (Jerry, Martin)

## What they are

One systemd-nspawn NixOS container per friend on bandit-lab, all built by the
same code: `hosts/bandit-lab/services/guest-box/` (`guests.nix` holds the
per-guest values, `default.nix` the container, firewall and slice, `watch.nix`
the audit rules and ntfy units, `report.sh`/`watch.sh` the scripts with the
guest's name swapped in). Contract check: `ci/lab-guests.nix`. Each box: pinned
user namespace, 1 CPU, no swap, 512 tasks, 50 GB `/data` (btrfs qgroup), own
tailnet node `tag:<name>-box`, root SSH by key only, NATed out, refused by the
host and walled off from LAN, bots, Docker and the other guest (forwarding
allowed to `enp44s0` only). Host auditd logs every exec; hourly ntfy report and
an ntfy notice per SSH login. The kernel is shared (`docs/SECURITY-PLAN.md` A6).

| Guest | uid base | veth (host/guest) | RAM | tag | extra |
| --- | --- | --- | --- | --- | --- |
| jerry | 524288 | 10.251.0.1 / .2 | 2 GB | `tag:jerry-box` | restic peer repo, host UDP 41641 (backup path) |
| martin | 655360 | 10.251.2.1 / .2 | 4 GB | `tag:martin-box` | nothing on the host is open to him |

(`10.251.1.0/30` and uid base 589824 belong to `mc-public`.)

**Shared pool.** Both containers run in `guests.slice`: together at most 2 CPUs
(`CPUQuota=200%`) and 6 GB (`MemoryMax=6G`), with `CPUWeight=20` and
`IOWeight=20` against the default 100 of `system.slice`, `user.slice` and
`machine.slice`. Under load the host's own services win and the two guests share
what is left; each guest keeps its own cap inside the pool.

## Jerry

Design: `docs/superpowers/specs/2026-11-01-jerry-guest-box-design.md`. Jerry
also has an append-only restic repository, `hosts/bandit-lab/services/backup/peer.nix`.

### Owner setup, in order

1. **Tailscale admin console.** Invite Jerry, then add to the policy file
   (`<jerry@example.com>` is his login):

   ```json
   "tagOwners": {"tag:jerry-box": ["autogroup:admin"]},
   "grants": [
     {"src": ["<jerry@example.com>"], "dst": ["tag:jerry-box"], "ip": ["tcp:22"]},
     {"src": ["<jerry@example.com>", "tag:jerry-box"], "dst": ["100.125.161.81"], "ip": ["tcp:8000"]},
     {"src": ["<jerry@example.com>", "tag:jerry-box"], "dst": ["svc:comfyui"], "ip": ["tcp:443"]}
   ]
   ```

   (The last line reaches the ComfyUI Tailscale Service, see
   `docs/runbooks/tailnet-services.md`.)

   (Equivalent `acls` entries: `<jerry@example.com> -> tag:jerry-box:22` and
   `<jerry@example.com>, tag:jerry-box -> 100.125.161.81:8000`.)
2. **Auth key.** Settings, Keys, Generate auth key: reusable off, ephemeral off,
   pre-authorized on, tag `tag:jerry-box`, 90-day expiry (used once).
3. **Secrets**, on the laptop from the repo root: `sops secrets/lab.yaml`. Add
   `jerry-tailscale-authkey` (the key from step 2), `restic-peer-prune-password-jerry`
   (new random passphrase) and append Jerry's htpasswd line to
   `restic-peer-htpasswd` (`nix shell nixpkgs#apacheHttpd -c htpasswd -nB jerry`).
4. **SSH key.** Paste Jerry's public key (collected out of band) into `jerry.key`
   in `hosts/bandit-lab/services/guest-box/guests.nix`, commit.
5. **Subvolumes**, as root on the lab, **before any push to `main`** (the hourly
   timer deploys it). The restic part is in
   [backup-peer.md, "Extra peer: jerry"](backup-peer.md#extra-peer-jerry); do not
   repeat it here. Additionally the box, owned by Jerry's mapped root (the
   container runs in a user namespace and could not write a uid-0 directory):

   ```bash
   btrfs subvolume create /srv/jerry/box && btrfs qgroup limit 50G /srv/jerry/box
   chown 524288:524288 /srv/jerry/box
   ```

   Warning: `restic-rest-server` has `RequiresMountsFor` on
   `/srv/backup/restic-peer/jerry`, so until `/srv/jerry/restic` exists the REST
   server does not start and the laptop's nightly backup to the lab fails too.
   If a subvolume was created after the mount unit had already failed:

   ```bash
   systemctl restart 'srv-backup-restic\x2dpeer-jerry.mount'
   systemctl restart restic-rest-server.service
   systemctl start restic-rest-server.socket
   ```
6. **Apply**: the first deploy is `lab-apply` from the laptop, not the timer, so a
   failing `container@jerry` is seen immediately. Push to `main` only after that.
7. **Tailnet IP.** Read the container's address:
   `ssh bandit-lab 'sudo nixos-container run jerry -- tailscale ip -4'`. Put
   Jerry's device IPs (the container's included, for backups from the box) into
   `extraPeers.jerry.ips` in `hosts/bandit-lab/services/backup/peer.nix`,
   commit, apply again. Until then nothing is admitted to port 8000.

### Checks

On the lab:

```bash
systemctl status container@jerry auditd jerry-ssh-watch jerry-restic-watch jerry-report.timer
ausearch -k jerry | tail
btrfs qgroup show -reF /srv/jerry/restic
iptables -S DOCKER-USER | grep ve-jerry                        # two DROP rules
stat -c %u /srv/jerry/box                                      # 524288
nixos-container run jerry -- touch /data/.w                    # /data is writable
machinectl status jerry | grep -i uid                          # user namespace base 524288
nixos-container run jerry -- tailscale status                  # joined the tailnet
ls -ln /var/lib/nixos-containers/jerry/var/lib/tailscale/      # authkey owned by 524288
journalctl -M jerry -u sshd -n 5                               # host can read the container journal
systemctl status jerry-report.timer
```

### Pause / remove

Pause: `systemctl stop container@jerry`. Remove: delete the Tailscale ACL rules
and the `tag:jerry-box` node, `nixos-container destroy jerry`,
`btrfs subvolume delete /srv/jerry/box /srv/jerry/restic`, drop the three jerry
secrets from `secrets/lab.yaml`, remove `jerry` from `guests.nix` and
`ci/lab-guests.nix` and the peer from `backup/peer.nix`.

### Handover to Jerry

Technical note, he knows the field.

- SSH: `ssh root@<container tailnet name>` (key only; tailnet ACL allows your login to port 22).
- Limits: 1 CPU, 2 GB RAM without swap (an OOM kill is yours to handle), 512
  tasks. `/data` is 50 GB; put models and data there. The rest of the root
  filesystem is not quota-counted but is not backed up either. Egress is NAT
  with DNS 9.9.9.9/1.1.1.1; no LAN, no other tailnet nodes.
- Backup: `rest:http://jerry:<pw>@100.125.161.81:8000/jerry/` with your own
  restic password. The repo is append-only, 512 GB quota; you cannot forget or
  prune. Retention is applied on the host: keep-daily 7, keep-weekly 5,
  keep-monthly 12, keep-yearly 2.
- Visibility: the owner receives an hourly report of the box's processes (names,
  exit codes and counts; no arguments) and an immediate notice on every SSH
  login and every backup session. Treat process names and logins as visible.
- No nix in the box (the host's nix daemon is not exposed to guests); use `uv`,
  pip, or static binaries under `/data`.
- The owner does not support software inside the container.

## Martin

A box like Jerry's without any backup on the lab: 1 CPU, 4 GB RAM, 50 GB
`/data`, `tag:martin-box`. The host refuses everything from `ve-martin` (no
port is open to him, unlike Jerry's UDP 41641).

### Owner setup, in order

1. **Tailscale admin console.** Invite Martin, then add to the policy file
   (`<martin@example.com>` is his login). He reaches only his box; the box
   reaches no tailnet node (no grant has `tag:martin-box` as `src`):

   ```json
   "tagOwners": {"tag:martin-box": ["autogroup:admin"]},
   "grants": [
     {"src": ["<martin@example.com>"], "dst": ["tag:martin-box"], "ip": ["tcp:22"]}
   ]
   ```

   Tests (save only if they pass):
   `{"src": "<martin@example.com>", "accept": ["tag:martin-box:22"], "deny": ["tag:jerry-box:22", "100.125.161.81:8000", "svc:comfyui:443"]}`
   and `{"src": "tag:martin-box", "deny": ["tag:jerry-box:22", "100.125.161.81:22"]}`.
2. **Auth key.** Settings, Keys, Generate auth key: reusable off, ephemeral off,
   pre-authorized on, tag `tag:martin-box`, 90-day expiry (used once).
3. **Secret**, on the laptop from the repo root: `sops secrets/lab.yaml`, add
   `martin-tailscale-authkey` (the key from step 2). Commit. The lab toplevel
   does not build without it.
4. **SSH key.** Paste Martin's public key (collected out of band) into
   `martin.key` in `hosts/bandit-lab/services/guest-box/guests.nix`, commit.
   Until then the box runs but nobody can log in by SSH.
5. **Subvolume**, as root on the lab, **before any push to `main`** (the hourly
   timer deploys it; without `/srv/martin/box` the container cannot start and
   the switch fails). One line each:

   ```bash
   mkdir -p /srv/martin
   btrfs subvolume create /srv/martin/box && btrfs qgroup limit 50G /srv/martin/box
   chown 655360:655360 /srv/martin/box
   ```
6. **Apply**: the first deploy is `lab-apply` from the laptop, not the timer, so
   a failing `container@martin` is seen immediately. Push to `main` only after
   that. This deploy also restarts `container@jerry` once (its unit moves to
   `guests.slice`); tell Jerry beforehand.

### Checks

On the lab:

```bash
systemctl status container@martin martin-ssh-watch martin-report.timer
systemctl show container@jerry container@martin -p Slice,CPUQuotaPerSecUSec,MemoryMax   # guests.slice, 1s, 2G / 4G
systemctl show guests.slice -p CPUQuotaPerSecUSec,MemoryMax,CPUWeight,IOWeight            # 2s, 6G, 20, 20
iptables -S DOCKER-USER | grep ve-martin                       # two DROP rules
iptables -S nixos-fw | grep ve-martin                          # one refuse, no accept
stat -c %u /srv/martin/box                                     # 655360
btrfs qgroup show -reF /srv/martin/box                         # 50 GiB limit
nixos-container run martin -- touch /data/.w                   # /data is writable
nixos-container run martin -- tailscale status                 # joined the tailnet
nixos-container run martin -- ping -c1 -W2 10.251.0.2          # fails: guest-to-guest is dropped
ausearch -k martin | tail
```

### Pause / remove

Pause: `systemctl stop container@martin`. Remove: delete the Tailscale ACL rule
and the `tag:martin-box` node, `nixos-container destroy martin`,
`btrfs subvolume delete /srv/martin/box`, drop `martin-tailscale-authkey` from
`secrets/lab.yaml`, remove `martin` from `guests.nix` and `ci/lab-guests.nix`.

### Handover to Martin

Send him, once his key is in and the box is on the tailnet:

- SSH: `ssh root@<container tailnet name>` (key only; the tailnet policy allows
  your login to port 22 of this box and nothing else on the lab).
- Limits: 1 CPU, 4 GB RAM without swap (an OOM kill is yours to handle), 512
  tasks; under load the lab's own services come first. `/data` is 50 GB; put
  your work there. The rest of the root filesystem is not quota-counted. Nothing
  is backed up: keep your own copies. Egress is NAT with DNS 9.9.9.9/1.1.1.1;
  no LAN, no other tailnet nodes.
- Visibility: the owner receives an hourly report of the box's processes (names,
  exit codes and counts; no arguments) and an immediate notice on every SSH
  login. Treat process names and logins as visible.
- No nix in the box; use `uv`, pip, or static binaries under `/data`.
- The owner does not support software inside the container.
