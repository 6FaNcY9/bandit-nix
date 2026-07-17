# Home Manager activation recovery

Use this when `nixos-rebuild` reports that `home-manager-vino.service` failed.

## Diagnose

```bash
systemctl status home-manager-vino.service
journalctl -u home-manager-vino.service -b --no-pager
```

The configuration uses a collision-proof backup command. If Home Manager must
replace an unmanaged file, the newest displaced file becomes `.hm-backup` and
older backups are numbered as `.hm-backup.~1~`, `.hm-backup.~2~`, and so on.
An existing backup therefore does not block a later activation.

## Retry safely

```bash
sudo nixos-rebuild test --flake .#bandit
bandit-health
```

Inspect the numbered backups before deleting or consolidating them. They may
contain local settings that were never declared in this repository. Once the
test activation and desktop session are healthy, make it persistent:

```bash
sudo nixos-rebuild switch --flake .#bandit
bandit-health
```

If activation still fails, use the first error emitted by `hm-activate-vino` in
the journal; the final systemd failure line is only a summary.
