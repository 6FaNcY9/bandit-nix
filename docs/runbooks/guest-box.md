# Guest boxes (Jerry, Martin)

## What they are

One systemd-nspawn container per friend on bandit-lab (Martin NixOS, Jerry Debian), all built by the
same code: `hosts/bandit-lab/services/guest-box/` (`guests.nix` holds the
per-guest values, `default.nix` the container, firewall and slice, `watch.nix`
the audit rules and ntfy units, `report.sh`/`watch.sh` the scripts with the
guest's name swapped in). Contract check: `ci/lab-guests.nix`. Each box: pinned
user namespace, 1 CPU, no swap, 512 tasks, 50 GB `/data` (btrfs qgroup), own
tailnet node `tag:<name>-box`, root SSH by key only, NATed out, refused by the
host (IPv4 after the guest's own accepts, IPv6 always) and walled off from LAN,
bots, Docker and the other guest: in the mangle table, forwarding from `ve-<name>`
is allowed to `enp44s0` only and never to 10/8, 172.16/12, 192.168/16,
169.254/16 or 100.64/10. Host auditd logs every exec; hourly ntfy report and
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

Design: `docs/superpowers/specs/2026-11-01-jerry-guest-box-design.md`; since 2026-11 a
Debian 13 rootfs run by the stock `systemd-nspawn@jerry`:
`docs/superpowers/specs/2026-11-16-guest-debian-design.md`. Jerry
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
   failing `systemd-nspawn@jerry` is seen immediately. Push to `main` only after that.
   A new box also needs its rootfs: steps 2 and 4 of the migration below.
7. **Tailnet IP.** Read the container's address:
   `ssh bandit-lab 'sudo systemd-run -M jerry -P -- tailscale ip -4'`. Put
   Jerry's device IPs (the container's included, for backups from the box) into
   `extraPeers.jerry.ips` in `hosts/bandit-lab/services/backup/peer.nix`,
   commit, apply again. Until then nothing is admitted to port 8000.

### Checks

On the lab:

```bash
systemctl status systemd-nspawn@jerry auditd jerry-ssh-watch jerry-restic-watch jerry-report.timer
ausearch -k jerry | tail
btrfs qgroup show -reF /srv/jerry/restic
iptables -t mangle -S FORWARD | grep ve-jerry                  # six DROP rules
stat -c %u /srv/jerry/box                                      # 524288
systemd-run -M jerry -P -- touch /data/.w                      # /data is writable
machinectl status jerry | grep -i uid                          # user namespace base 524288
systemd-run -M jerry -P -- tailscale status                    # joined the tailnet
ls -ln /var/lib/machines/jerry/var/lib/tailscale/             # authkey owned by 524288
journalctl -M jerry -u ssh -n 5                                # host can read the container journal
systemctl status jerry-report.timer
```

### Pause / remove

Pause: `machinectl poweroff jerry`. That holds only until the next deploy or
reboot (`multi-user.target` wants the unit; `systemctl disable` does not work on
NixOS). To keep it off, also move the seed marker away, so the unit and its ssh
watcher are skipped: `mv /var/lib/machines/jerry/etc/guest-seeded /var/lib/machines/jerry/etc/guest-seeded.off`.
Resume: move it back, `systemctl start systemd-nspawn@jerry`. Remove:
delete the Tailscale ACL rules and the `tag:jerry-box` node, stop the box,
`btrfs subvolume delete /var/lib/machines/jerry /srv/jerry/box /srv/jerry/restic`, drop the three jerry
secrets from `secrets/lab.yaml`, remove `jerry` from `guests.nix` and
`ci/lab-guests.nix` and the peer from `backup/peer.nix`.

### Migration to Debian (2026-11)

From the NixOS `container@jerry` to a Debian rootfs in `/var/lib/machines/jerry`.
`guest-debian-init jerry` (root, on the lab) debootstraps trixie, adds Tailscale
and `uv`, reinstalls with apt what Jerry installed by hand in his proot Debian
(`/srv/jerry/box/debian/rootfs`), copies the seed files from `/etc/guest-seed/jerry`,
the old tailscale state and SSH host keys from `/var/lib/nixos-containers/jerry`,
and the old `/root` to `/srv/jerry/box/old-root`. It writes the marker
`/var/lib/machines/jerry/etc/guest-seeded` last; the unit does not start without it.

1. Tell Jerry: everything outside `/data` is replaced; `/root` lands in
   `/data/old-root`, the apt reinstall list in `/data/old-root/apt-reinstall.txt`.
2. Lab: `sudo btrfs subvolume create /var/lib/machines/jerry && sudo btrfs qgroup limit 20G /var/lib/machines/jerry`.
3. Laptop: signed merge, `lab-apply` (stops `container@jerry`; the new unit and
   `jerry-ssh-watch` are skipped until the seed marker exists). Then on the lab
   `systemctl is-active container@jerry` must say `inactive`; otherwise
   `sudo systemctl stop container@jerry`. A failed deploy is retried only after a
   new commit or `sudo rm /var/lib/lab-update/failed-candidate`.
4. Lab: `sudo guest-debian-init jerry`, then `sudo systemctl start systemd-nspawn@jerry`
   (this also starts `jerry-ssh-watch`; no separate start needed).
   It refuses before writing anything when a guest path is a symlink, the old box has
   no tailscale state, or the old `/root` does not fit under the `/data` qgroup.
   Packages his old Debian had but trixie lacks are only listed under `missing:`.
   It refuses a non-empty rootfs: after a failed run delete and recreate the
   subvolume (step 2), then run it again.
5. Checks: the list above, plus:

   ```bash
   machinectl status jerry | grep -i uid                          # 524288
   ip addr show ve-jerry                                          # 10.251.0.1/32
   systemd-run -M jerry -P -- systemctl is-active ssh tailscaled systemd-networkd
   systemd-run -M jerry -P -- tailscale ip -4                     # 100.102.212.56, else a new node: fix peer.nix
   systemd-run -M jerry -P -- cat /etc/resolv.conf                # 9.9.9.9 and 1.1.1.1
   systemd-run -M jerry -P -- apt-get install -y sl
   systemctl show systemd-nspawn@jerry -p Slice,MemoryMax         # guests.slice, 2G
   ```

   Then the port probe as for Martin, an ssh login ntfy and a restic run.

Rollback: the revert does not stop the Debian box (a template instance), and if it
still runs both boxes fight over `ve-jerry` and the node key. So, on the lab
immediately before `lab-apply` of the signed revert: `sudo systemctl stop systemd-nspawn@jerry`.
After it, `systemctl is-active systemd-nspawn@jerry` must say `inactive`
(else stop it again and `sudo systemctl restart container@jerry`); the old rootfs in
`/var/lib/nixos-containers/jerry` boots as before. Keep it about two weeks, then
`btrfs subvolume delete /var/lib/nixos-containers/jerry` if it is a subvolume.

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
- Debian 13 (trixie): `apt install` as root works; `uv` is in `/usr/local/bin`.
  The host does not update the inside; `unattended-upgrades` installs security updates.
- The owner does not support software inside the container.

## Martin

A box like Jerry's without any backup on the lab: 1 CPU, 4 GB RAM, 50 GB
`/data`, `tag:martin-box`. The host refuses everything from `ve-martin` (no
port is open to him, unlike Jerry's UDP 41641).

**Shared box (since 2026-11).** The box is now for several friends and is called
`guest-box` in the tailnet (`tailscale set --hostname`); inside the lab it is still
`martin` (unit, `tag:martin-box`, secret, `/srv/martin`). Nobody is root. Each
friend has a normal account (home 0700, no sudo, own folder `/data/<name>`) and
they all share the box's 1 CPU / 4 GB. Add a friend:

1. Tailscale: invite them, then add their login to the grant
   `{"src": [...], "dst": ["tag:martin-box"], "ip": ["tcp:22"]}` and copy
   Martin's two deny tests for the new login.
2. Add `<name> = "ssh-ed25519 ...";` under `martin.users` in `guests.nix` and
   the name to `expect.martin.users` in `ci/lab-guests.nix`. Deploy.
3. Handover: `ssh <name>@guest-box` (no password, key only).

### Owner setup, in order

1. **Tailscale policy first** (Access controls, JSON editor), before Martin is
   invited (`<martin@example.com>` is the login he will use). He reaches only
   his box; the box reaches no tailnet node (no grant has `tag:martin-box` as
   `src`):

   ```json
   "tagOwners": {"tag:martin-box": ["autogroup:admin"]},
   "grants": [
     {"src": ["<martin@example.com>"], "dst": ["tag:martin-box"], "ip": ["tcp:22"]}
   ]
   ```

   Tests under `"tests"` (save only if they pass):

   ```json
   {"src": "<martin@example.com>", "accept": ["tag:martin-box:22"], "deny": ["tag:jerry-box:22", "100.125.161.81:22", "100.125.161.81:445", "100.125.161.81:8000", "100.125.161.81:25565", "svc:grafana:443", "svc:beszel:443", "svc:cockpit:443", "svc:ntopng:443", "svc:comfyui:443", "svc:memory:443", "svc:memory-albert:443", "svc:memory-firma:443", "svc:bnet:443"]},
   {"src": "tag:martin-box", "deny": ["tag:jerry-box:22", "100.125.161.81:22", "100.125.161.81:445", "100.125.161.81:8000", "100.125.161.81:25565", "svc:grafana:443", "svc:beszel:443", "svc:cockpit:443", "svc:ntopng:443", "svc:comfyui:443", "svc:memory:443", "svc:memory-albert:443", "svc:memory-firma:443", "svc:bnet:443"]}
   ```

   Then invite Martin.
2. **Auth key.** Settings, Keys, Generate auth key: reusable off, ephemeral off,
   pre-authorized on, tag `tag:martin-box`, 90-day expiry (used once). Revoke
   it in the console once the box has joined (step 7).
3. **Secret**, on the laptop from the repo root: `sops secrets/lab.yaml`, add
   `martin-tailscale-authkey` (the key from step 2). Commit. The lab toplevel
   does not build without it.
4. **SSH key.** Paste Martin's public key (collected out of band) into
   `martin.key` in `hosts/bandit-lab/services/guest-box/guests.nix`, commit.
   Until then the box runs but nobody can log in by SSH.
5. **Subvolumes**, as root on the lab, **before any push to `main`** (the hourly
   timer deploys it; without `/srv/martin/box` the container cannot start and
   the switch fails). The second one caps the container's root filesystem,
   which otherwise has no quota; it must exist before the first start (the
   container module only runs `mkdir -p` in it, and nspawn chowns it to
   655360 on first boot). One line each:

   ```bash
   mkdir -p /srv/martin
   btrfs subvolume create /srv/martin/box && btrfs qgroup limit 50G /srv/martin/box
   chown 655360:655360 /srv/martin/box
   btrfs subvolume create /var/lib/nixos-containers/martin && btrfs qgroup limit 20G /var/lib/nixos-containers/martin
   ```

   (A nested subvolume is not part of snapshots of `/`; nothing in the box is
   backed up anyway.)
6. **Apply**: the first deploy is `lab-apply` from the laptop, not the timer, so
   a failing `container@martin` is seen immediately. Push to `main` only after
   that. This deploy also restarts `container@jerry` once (its unit moves to
   `guests.slice`); tell Jerry beforehand.
7. **After the deploy**: run the checks below, then revoke the auth key from
   step 2 and do the handover.

### Checks

On the lab:

```bash
systemctl status container@martin martin-ssh-watch martin-report.timer
systemctl show systemd-nspawn@jerry container@martin -p Slice,CPUQuotaPerSecUSec,MemoryMax   # guests.slice, 1s, 2G / 4G
systemctl show guests.slice -p CPUQuotaPerSecUSec,MemoryMax,CPUWeight,IOWeight            # 2s, 6G, 20, 20
iptables -t mangle -S FORWARD | grep ve-                        # six DROP rules per guest
iptables -S nixos-fw | grep ve-martin                          # one refuse, no accept
ip6tables -S nixos-fw | head -3                                # ve-jerry and ve-martin refuses on top
ip -6 route show dev ve-martin                                 # only fe80::/64
stat -c %u /srv/martin/box                                     # 655360
btrfs qgroup show -reF /srv/martin/box                         # 50 GiB limit
btrfs qgroup show -reF /var/lib/nixos-containers/martin        # 20 GiB limit
nixos-container run martin -- touch /data/.w                   # /data is writable
nixos-container run martin -- tailscale status                 # joined the tailnet
nixos-container run martin -- curl -sI https://example.com    # egress works
ausearch -k martin | tail
```

Must print only `closed` lines (host, LAN, router, tailnet, the other boxes,
Podman, the bots bridge, Docker). The one exception allowed is
`100.100.100.100/53`: that is the box's own tailscaled resolver, not the host.

```bash
nixos-container run martin -- bash -c 'for t in 10.251.2.1/22 192.168.0.160/22 192.168.0.1/80 100.125.161.81/22 100.100.100.100/53 10.251.0.2/22 10.251.1.2/25565 10.89.0.1/25565 10.250.77.1/25575 172.17.0.1/22; do timeout 3 bash -c "</dev/tcp/$t" 2>/dev/null && echo "OPEN $t" || echo "closed $t"; done'
```

### Pause / remove

Pause: `systemctl stop container@martin`. Remove: delete the Tailscale ACL rule
and the `tag:martin-box` node, `nixos-container destroy martin`,
`btrfs subvolume delete /srv/martin/box /var/lib/nixos-containers/martin`, drop `martin-tailscale-authkey` from
`secrets/lab.yaml`, remove `martin` from `guests.nix` and `ci/lab-guests.nix`.

### Handover to Martin

Send him, once his key is in and the box is on the tailnet:

- SSH: `ssh <name>@guest-box` (key only; the tailnet policy allows
  your login to port 22 of this box and nothing else on the lab).
- Limits: 1 CPU, 4 GB RAM without swap (an OOM kill is yours to handle), 512
  tasks; under load the lab's own services come first. `/data/<name>` is your part of 50 GB; put
  your work there. The rest of the root filesystem is capped at 20 GB. Nothing
  is backed up: keep your own copies. Egress is NAT with DNS 9.9.9.9/1.1.1.1;
  no LAN, no other tailnet nodes.
- Visibility: the owner receives an hourly report of the box's processes (names,
  exit codes and counts; no arguments) and an immediate notice on every SSH
  login. Treat process names and logins as visible.
- No nix in the box; use `uv`, pip, or static binaries under `/data`.
- The owner does not support software inside the container.
