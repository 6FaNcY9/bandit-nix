# bandit-lab updates and rollback

The timer only fetches metadata and reports whether `origin/main` is newer. It
does not build or activate updates.

## Review and apply

```bash
sudo lab-update check
sudo git -C /etc/nixos/bandit-nix log --oneline HEAD..origin/main
sudo lab-update apply
sudo bandit-lab-health
```

The apply path refuses a dirty checkout or a non-fast-forward change. It builds
the fetched commit directly with at most two concurrent jobs and four cores per
job. It then runs a test activation and the lab health check, switches, and
checks health again. The checkout advances only after those steps succeed.
The health check also requires the standard tty1 getty to remain active. Public
HTTPS is read-only and requires no deploy key.

## Inspect failures

```bash
systemctl status lab-update-check.service
journalctl -u lab-update-check.service -b --no-pager
systemctl --failed
sudo bandit-lab-health
```

If activation or health validation fails, `lab-update` restores the previous
system profile automatically. Confirm it with:

```bash
readlink -f /run/current-system
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

For a later manual rollback, choose a known-good generation with
`sudo nixos-rebuild switch --rollback`, then rerun `bandit-lab-health`.
