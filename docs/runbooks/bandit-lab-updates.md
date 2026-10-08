# bandit-lab updates and rollback

Automatic updates are **paused**: `lab-update-apply.timer` is disabled in
`hosts/bandit-lab/services/auto-rebuild/default.nix` (`enable = false`), so
nothing is applied until someone runs `sudo lab-update apply`. To resume the
hourly signed update (up to ten minutes of randomized delay, fetching
`origin/main` itself), set `enable = true` again and deploy that change.

Until the pause itself has been deployed, a timer that is already running on the
host keeps firing. `systemctl disable` does not work on NixOS (the unit links
live in the read-only Nix store), so stop it with a runtime mask, which lasts
until the next reboot:

```bash
sudo systemctl mask --runtime --now lab-update-apply.timer
# undo before re-enabling the timer without a reboot:
sudo systemctl unmask --runtime lab-update-apply.timer
```

The `lab-update-check.service` unit still exists for on-demand checks
(`sudo lab-update check` or `sudo systemctl start lab-update-check`); only its
timer was removed.

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
checkout advances only after those steps succeed. Only fast-forward updates
are applied (see below). Public HTTPS is read-only and requires no deploy key.

The headless health policy intentionally excludes `getty@tty1.service`.

## Fast-forward only (downgrade protection)

`lab-update apply` deploys a new `origin/main` only if the commit the lab
currently has checked out is an ancestor of it. Two cases are refused before any
build or activation, even when the commit is validly signed:

- **downgrade**: `origin/main` was moved back to an older commit, for example
  one from before a password rotation;
- **diverged**: history was rewritten (rebase or force-push).

`sudo lab-update check` reports these as `Non-fast-forward (downgrade|diverged)
... lab-update apply will refuse it` and changes nothing. Refusals exit with
status 1 and the message `Refusing downgrade update ...`.

If a rewrite is intended and you have reviewed it (for example you really did
rebase `main` yourself), run the explicit override by hand:

```bash
sudo lab-update apply --allow-non-ff
```

It warns, builds, activates and health-checks as usual, then hard-resets the
mirror checkout to the deployed commit. The flag only works with `apply`, no
systemd unit may pass it (the `lab-update` flake check fails if one does), and
it must never be added to a timer.

The updater fetches `main` with an explicit refspec and no tags and resolves
only `refs/remotes/origin/main`. (A bare `origin/main` is ambiguous and git
prefers a *tag* of that name, which would let a pushed tag pick what is
deployed; a regression test covers this.) `--allow-non-ff` is refused whenever
`INVOCATION_ID` shows the updater runs inside a systemd unit, so even a wrapper
script cannot enable it unattended. Check once on the lab that a normal sudo
session is unaffected: `sudo env | grep -c INVOCATION_ID` must print `0`.

Residual risks, stated honestly:

- The gate enforces ancestry, not "was on `main`". Any commit signed by a
  trusted key that descends from the deployed commit is accepted, including a
  signed revert, a signed merge that brings old content back, or an unmerged
  side-branch commit force-pushed onto `main`. Only the tip signature is
  checked, not the commits between the deployed one and the tip. The signing
  keys and GitHub access therefore remain the root of trust; see the key
  sections below.
- The anchor is the checkout at `/etc/nixos/bandit-nix`. Never move its HEAD by
  hand (`git pull`, `git reset`): that is equivalent to `--allow-non-ff`.
  Deleting or re-cloning the checkout is trust-on-first-use with no anchor and
  skips the Vaultwarden guard (the diff is empty), so treat it as a manual,
  reviewed action.
- If the machine loses power between the final `switch` and the checkout
  fast-forward, the system runs the new commit while the anchor is one step
  behind until the next successful run.
- `sudo lab-update check` exits 0 even for a refused non-fast-forward; the
  refusal shows up when `apply` runs.

## GitHub branch protection (manual, owner only)

Make GitHub refuse the history rewrite in the first place. This is a one-time
setting that cannot be done from this repository. Steps, using GitHub's rulesets
([documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)):

1. Open the repository on GitHub and click **Settings**.
2. In the left sidebar, under "Code, planning, and automation", click
   **Rulesets**, then **New ruleset**, then **New branch ruleset**.
3. Name it, for example `protect main`. Set **Enforcement status** to
   **Active**.
4. Under **Target branches**, click **Add a target** and choose
   **Include default branch**.
5. Leave the **Bypass list** empty so that nobody, including you, can push
   around the rules.
6. Tick **Restrict deletions** and **Block force pushes**.
7. Optional but recommended: tick **Require signed commits**. Your commits are
   signed with `4D8770567A65FE1369E2BCC1611871842A8C1619`, which GitHub accepts
   once the key is on your account. Web merges made on github.com carry
   GitHub's own signature, which the lab does not trust, so merge locally and
   push.
8. Click **Create**.

To confirm it works, try a harmless force-push to a scratch branch name that the
ruleset does not cover (it will succeed) and then to `main` (it must be
rejected); do not test with real history.

## If the phone signing key is lost or exposed

The lab trusts two keys (see `auto-rebuild/default.nix`): the laptop key and a
phone key. The phone key is the more exposed one. If the phone is lost, stolen
or compromised:

1. **Stop deployments from the phone key at once.** On the laptop, remove the
   phone key from the updater:
   - delete `hosts/bandit-lab/services/auto-rebuild/lab-update-phone-signing-key.asc`;
   - remove `phoneSigningKeyFingerprint`, the second `--import` argument and the
     phone line of the `--import-ownertrust` printf in
     `hosts/bandit-lab/services/auto-rebuild/default.nix`.
   Commit signed with the laptop key, push to `main`, then run
   `sudo lab-update apply` on the lab. Until that apply finishes the lab still
   trusts the phone key.
2. **Cut off GitHub access from the phone.** On github.com open **Settings**,
   then **SSH and GPG keys**, and delete the phone's SSH and GPG keys. Under
   **Settings**, **Applications**, revoke authorised apps and tokens used from
   the phone, and sign out its sessions.
3. **Revoke the key.** Use the revocation certificate you made when creating
   the key and publish the revoked key to GitHub. If no certificate exists the
   lost key cannot be revoked, but steps 1 and 2 already remove its power
   (generate and store an offline revocation certificate for every signing key
   you keep).
4. **Review what was pushed.** Compare `git log origin/main` against what you
   remember pushing since the phone was last under your control. A fast-forward
   commit signed by the phone key would have been accepted by the lab.
5. Keep the lab on manual apply until this is done (the timer is paused
   already).

## If Tailscale is down (SSH recovery)

sshd, SMB and Minecraft are reachable over the tailnet only, and the public
Cloudflare SSH route is gone. `bandit-lab-health` fails a deployment (and
`lab-update` rolls back) when `tailscale status` is not `Running`, so a bad
update cannot silently lock you out. If Tailscale breaks anyway (account
expiry, outage, broken state), recover at the machine itself:

1. Log in on the lab's own keyboard and screen (it is a laptop).
2. Look at the service: `systemctl status tailscaled` and `tailscale status`.
3. Restart it: `sudo systemctl restart tailscaled`. If it reports that the
   machine needs to log in, run `sudo tailscale up` and open the printed link
   on another device.
4. Confirm from the laptop: `ssh bandit-lab`.
5. If a configuration change caused it, roll back: `sudo nixos-rebuild switch
   --rollback`, then `bandit-lab-health`.

Do not add a LAN or public SSH route as a workaround; decision D6 chose
Tailscale only.

Prevent the commonest cause, node-key expiry: in the Tailscale admin console
(machines list, the menu of `bandit-lab`) choose **Disable key expiry**, and
check it with `tailscale status --json | jq .Self.KeyExpiry` (empty or null
means no expiry). Also keep an eye on ACL changes, which can cut the laptop off
without any change on the lab.

## Vaultwarden changes

Automatic apply refuses a signed revision that changes
anything under `hosts/bandit-lab/services/vaultwarden/`. NixOS rollback restores configuration and
services, but it does not restore persistent Vaultwarden data under
`/srv/containers/vaultwarden/data`.

Apply Vaultwarden changes only during supervised maintenance, after taking a
consistent, verified backup of that data. Confirm the backup can be restored
before using a supervised deployment procedure; the unattended apply guard
must not be bypassed casually.

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
