# bandit-lab updates and rollback

Two persistent timers manage updates:

- `lab-update-check.timer` checks `origin/main` every ten minutes and reports
  whether a newer revision exists.
- `lab-update-apply.timer` attempts a signed update hourly, with up to ten
  minutes of randomized delay.

For manual-only control, disable the apply timer while leaving update checks
enabled:

```bash
sudo systemctl disable --now lab-update-apply.timer
```

## Review and apply

```bash
sudo lab-update check
sudo git -C /etc/nixos/bandit-nix log --oneline HEAD..origin/main
sudo lab-update apply
sudo bandit-lab-health
```

The apply path refuses a dirty checkout and requires a commit signed by one of
the configured deployment keys. It builds the fetched commit directly with at
most two concurrent jobs and four cores per job. It then test-activates the
candidate, runs the lab health check, switches, and checks health again. The
checkout advances only after those steps succeed. A signed non-fast-forward
update is permitted with a warning and recorded only after successful
activation. Public HTTPS is read-only and requires no deploy key.

The headless health policy intentionally excludes `getty@tty1.service`. Ollama
and its dependent LLM log monitor are also temporarily parked: their Nix modules
and `/srv/ollama` data remain available for later reactivation, but they are not
installed or treated as deployment gates.

## Inspect failures

```bash
systemctl status lab-update-check.service
journalctl -u lab-update-apply.service -b --no-pager
journalctl -u lab-update-check.service -b --no-pager
systemctl --failed
sudo bandit-lab-health
```

If activation or health validation fails, `lab-update` re-tests or restores the
previous system configuration automatically. Confirm the live system and
profile history with:

```bash
readlink -f /run/current-system
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

For a later manual rollback, choose a known-good generation with
`sudo nixos-rebuild switch --rollback`, then rerun `bandit-lab-health`.

After deploying the parked-Ollama configuration, an old failed unit may remain
in systemd's failure history even though it is no longer installed. Clear only
that stale marker with `sudo systemctl reset-failed ollama.service`, then rerun
`systemctl --failed` and `sudo bandit-lab-health`.
