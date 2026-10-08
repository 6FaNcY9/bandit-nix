# Peer backups: bandit and bandit-lab back each other up (restic over Tailscale)

A free second copy ("duct-tape NAS"). Each host runs an append-only restic
REST server on its own tailnet address and pushes to the other. Independent of
the Backblaze job (`docs/runbooks/backup-restore.md`), which can be added later
as a third copy.

| | Laptop `bandit` | Lab `bandit-lab` |
| --- | --- | --- |
| REST server | `100.102.247.30:8000`, data in `/var/lib/restic-peer` | `100.125.161.81:8000`, data in `/srv/backup/restic-peer` |
| Hosts the repo of | `lab` (user `lab`, `/var/lib/restic-peer/lab`) | `bandit` (user `bandit`, `/srv/backup/restic-peer/bandit`) |
| Quota | 150 GiB (`maxSize` in `nixos/backup-peer.nix`) | none (2.4 TB free) |
| Pushes | `restic-backups-peer.service` at 11:30, 15:30, 20:30 (+15 min jitter, `Persistent`) | `restic-backups-peer.service` at 05:30 (+20 min jitter, `Persistent`) |
| Retries | on failure every 20 min, 4 tries per 2 h; skipped on battery (`ConditionACPower`) | on failure every hour, 6 tries per 12 h, then `failed` (alert) |
| Applies retention (`forget --prune`, weekly Sun 07:30) | the lab's repo (`restic-peer-prune`) | the laptop's repo (`restic-peer-prune`) |

Retention (`repoConfig.backupPeer.retention`, shared with the Backblaze job):
7 daily, 5 weekly, 12 monthly, 2 yearly. Clients cannot delete (append-only);
each server prunes locally with the other side's repository password.

What is backed up
- Lab: exactly the Backblaze set (`hosts/bandit-lab/services/backup/shared.nix`:
  Vaultwarden, AiiA/Ghost DB + content, PostgreSQL dumps, Mrija mail, Minecraft
  snapshot). Same prepare logic, separate staging dir `/var/backup/restic-staging-peer`;
  the unit is ordered after `restic-backups-lab.service` so they never overlap.
- Laptop: the `include` list in `nixos/backup-peer.nix` (home-relative, missing
  entries are skipped): `src`, `.ssh`, `.gnupg`, `Documents`, `Pictures`, Prism
  Launcher `saves/config/xaero*/screenshots`. Excludes: `node_modules`, `.direnv`,
  `result`, `result-*`, `target`, `.cache`, `Downloads`, `.venv`, `__pycache__`.
  The sops age key (`~/.config/sops/age`) is intentionally not included.

Security model: the port is opened only on `tailscale0` and only from the peer's
/32 (iptables, `networking.firewall.extraCommands`), the server binds only the
host's own tailnet IP, so other tailnet nodes (friends) cannot reach it. Each
client has its own htpasswd user and private repository; the repo is also
encrypted with its own password. The socket-activated rest-server uses
`FreeBind`, so it starts before tailscaled has its address (no retry loop needed).
Plain HTTP is acceptable only because WireGuard encrypts the tailnet.

## Deploy (order matters)

Nix declares eight new sops keys; if they do not exist yet, `sops-isolation`
fails and activation of the new generation fails. So:

1. **Owner, laptop, from the repo root** (before any switch):
   `bash tools/backup-peer-secrets.sh secrets`
   It generates four random passwords in memory, derives every URL / bcrypt
   htpasswd line from them in the same run, and writes (nothing is printed):

   `secrets/bandit.yaml` (laptop): `restic-peer-repository` (`rest:http://bandit:<pw>@100.125.161.81:8000/bandit/`),
   `restic-peer-password`, `restic-peer-htpasswd` (user `lab`), `restic-peer-prune-password` (lab repo password).

   `secrets/lab.yaml` (lab): `restic-peer-repository` (`rest:http://lab:<pw>@100.102.247.30:8000/lab/`),
   `restic-peer-password`, `restic-peer-htpasswd` (user `bandit`), `restic-peer-prune-password` (laptop repo password).

   It refuses to overwrite existing keys. Commit the two yaml files with the Nix
   change. Keep an offline copy of your sops age key: the repository passwords
   live only in sops.
2. Switch the laptop (`nixos-rebuild switch`), then apply the lab as usual
   (`lab-update`). Check `systemctl status restic-rest-server.socket` on both.
3. `bash tools/backup-peer-secrets.sh init` (laptop; optional because the jobs use
   `initialize = true`, but it proves both servers, passwords and the firewall work).
4. Kick the first runs: `sudo systemctl start restic-backups-peer` on each host
   (the laptop's first run is large; keep it on AC).

## Check

- `systemctl list-timers 'restic-*'` and `systemctl status restic-backups-peer` on both hosts.
- Snapshots: `sudo restic-peer snapshots` (wrapper created by the module, uses the job's repository and password).
- Lab alerting: `restic-backups-peer.service` and `restic-peer-prune.service` are in the "Backup job failed" alert; `bandit-lab-health` is unaffected unless a unit is `failed`.
- Server side, direct: `sudo -u restic restic -r /var/lib/restic-peer/lab --password-file /run/secrets/restic-peer-prune-password check` (laptop; on the lab use `/srv/backup/restic-peer/bandit`).
- Laptop has no alerting: a failed run shows in `bandit-health` (`systemctl --failed`).

## Restore

From the machine that lost data (the sops secrets, or the owner's copies, give URL and password):
```bash
# laptop data, from the lab:
sudo restic-peer snapshots
sudo restic-peer restore latest --target /tmp/restore --include /home/vino/src
# lab data, from the laptop (lab is gone: export the URL/password from secrets/lab.yaml):
RESTIC_REPOSITORY=$(sops decrypt --extract '["restic-peer-repository"]' secrets/lab.yaml) \
RESTIC_PASSWORD=$(sops decrypt --extract '["restic-peer-password"]' secrets/lab.yaml) \
  restic restore latest --target /tmp/lab-restore
```
or, if the lab is down, restore straight from the files on the laptop:
`restic -r /var/lib/restic-peer/lab --password-file <(sops decrypt --extract '["restic-peer-prune-password"]' secrets/bandit.yaml) restore latest --target ...`.
Restore into a new directory; databases come back as dumps in
`restic-staging-peer/` (see backup-restore.md for importing them).

## Offline behaviour and disk space

- Laptop asleep/off or off the tailnet: the lab job fails, retries hourly 6 times,
  goes `failed` (alert), and is tried again by the next 05:30 timer; `Persistent`
  makes up a missed run once the lab is up. Lab unreachable: the laptop job retries
  every 20 min and again at the next of its three daily slots.
- Append-only: neither host can be tricked into deleting the other's history,
  but disk only grows until the weekly prune runs.
- Laptop has about 379 GB free; the lab's repo on it is capped at 150 GiB. When
  the lab job fails with a quota error, free space on the laptop and raise
  `maxSize` (or exclude large paths in `shared.nix`). The lab's staging copies live on `/` (2.4 TB free).
- First lab run may be slow: `TimeoutStartSec` is 12 h.

## Adding Backblaze as a third copy

Already prepared: set `bandit-lab.backups.enable = true;` after
`tools/add-backup-secrets.sh` (see backup-restore.md). It uses the same data
(`shared.nix`) and the same retention, with its own staging dir and 04:30 timer.
