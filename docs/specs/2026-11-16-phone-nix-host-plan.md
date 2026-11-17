# Phone as a Nix host (`pong`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The phone's command-line environment, root tools included, comes from this repo as
host `pong`, runs in a root chroot with real Nix, and can be restored after a reset.

**Architecture:** A root chroot at `/data/nix-root` holds `/nix` and a minimal glibc root.
`pong-nix-enter` (run from Termux) opens a private mount namespace, binds the Android paths
in, chroots, drops to the Termux uid and starts the Home Manager shell. The repo gains an
`aarch64-linux` standalone Home Manager output `homeConfigurations."vino@pong"` that reuses
the laptop's terminal modules. A Termux rescue kit stays outside Nix.

**Tech Stack:** Nix (single-user, official aarch64 tarball), Home Manager, sops-nix (HM
module), Bitwarden CLI, POSIX sh scripts on Android (toybox + KSU `su`), Python 3 (`pkt`).

**Spec:** `docs/specs/2026-11-16-phone-nix-host-design.md`

## Global Constraints

- Never write `boot_a`/`boot_b`, `vendor_boot`, `dtbo`, `vbmeta*`; never reboot the phone.
- Never copy, encrypt or commit `keybox.xml`, `tricky_store/{boot_key,hbk,keys}`,
  `~/kb*.xml`, `~/kb_cert*`, `~/cert_*.pem`. This repo is **public**.
- No change under `/data/adb` without the owner's OK for that change, after a copy to
  `/data/adb/claude_backup_<YYYYMMDD>/`. The plan needs none.
- Mounts exist only in the private namespace of a `pong-nix-enter` session; no app may see
  them. Play Integrity must stay STRONG.
- Root tools call KSU's own binaries in `/data/adb/ksu/bin` and `/data/adb/ksud`; Nix never
  ships `magiskboot`, `bootctl`, `ksu_susfs` or `ksud`.
- The Termux rescue kit (`pkt` + its Python, `boot-backup.sh`, `root-doctor.sh`, `openssh`,
  `git`, Claude Code Termux build, `termux-api`) is never removed and must keep working when
  the chroot is unreachable.
- `bandit`, `bandit-ci`, `bandit-lab` must evaluate to the same derivations as before.
- No heavy builds on the phone; the phone substitutes from `cache.nixos.org`. The laptop
  cannot build `aarch64-linux` (no binfmt); CI builds `pong` on `ubuntu-24.04-arm`.
- Session src-4c owns the laptop terminal look (`modules/user/desktop`, `home/terminal` look). Task 2 only moves imports; it must not change any laptop derivation (Task 2 Step 3 proves it). Tell src-4c via the shared note before merging.
- No push to `origin` without the owner's OK (a push to `main` deploys bandit-lab).
- Phone facts: Termux uid/gid `10417`, Android 16, SELinux enforcing, `/data` f2fs
  `nosuid,nodev`, Termux home `/data/data/com.termux/files/home`.

## Decision that refines the spec

The spec says the home stays the Termux home. Home Manager would then write `~/.ssh/config`,
`~/.gitconfig` etc. as links into `/nix/store`, which do not exist outside the chroot, and
the Termux rescue kit's `ssh` and `git` would break. So: **inside the chroot `HOME` is
`/home/vino`** (on `/data/nix-root`), and the shared state is reached through symlinks that
point at the Termux home (`~/projects`, `~/src`, `~/.claude`, `~/.claude.json`,
`~/storage`). The Termux home itself is never written by Home Manager. Update the spec's
"Runtime on the phone" section in Task 1's commit.

## Review Focus

1. **Chroot entry fails** (no `su`, `CapEff=0`, slot B without KSU): Termux must still give
   a working Termux shell with a one-line reason, never hang or close. Test in Task 1.
2. **Termux side after a Home Manager switch:** `ssh -G pc` and `git config -l` run in plain
   Termux must still succeed. Test in Task 3.
3. **Mount leaks:** after two sessions opened and closed, no app process (and not
   `/proc/1/mountinfo`) shows `nix-root`. Test in Task 1.
4. **Reboot:** after a phone reboot (done by the owner, not by us), `pong-nix-enter` works
   with no extra step. Check listed in Task 9's runbook drill.
5. **Network inside the chroot:** DNS and sockets work (Android needs group `3003` inet and
   has no `/etc/resolv.conf`): `curl -sI https://cache.nixos.org` and `ssh -o BatchMode=yes pc true`
   succeed. Test in Task 1 (curl) and Task 4 (ssh).

---

### Task 1: Spike — chroot, Nix, entry script, hiding check (gate for everything else)

**Files:**
- Create: `hosts/pong/bootstrap/pong-nix-install` (POSIX sh, run as Termux user, uses `su`)
- Create: `hosts/pong/bootstrap/pong-nix-enter` (POSIX sh)
- Create: `hosts/pong/bootstrap/pong-hide-check` (POSIX sh)
- Modify: `docs/specs/2026-11-16-phone-nix-host-design.md` (home decision above)

**Interfaces:**
- Produces: env `PONG_NIX_ROOT` (default `/data/nix-root`) read by all three scripts, and
  `PONG_SU` (default `su`) used for every root call, so tests can simulate no root.
- Produces: `pong-nix-enter [cmd...]` — no args: login shell; with args: runs `cmd` inside
  and exits with its status. Exit `2` with message `pong-nix: no root` if `su` fails.
  Sets `PONG_NIX=1` inside.
- Produces: `pong-hide-check` — exit 0 and print `OK hidden` if no line containing
  `$PONG_NIX_ROOT` is in `/proc/1/mountinfo` or the mountinfo of 3 non-Termux app pids;
  else exit 1 listing them.
- Produces (chroot layout): `/nix`, `/home/vino` (owned 10417), `/etc/passwd` with
  `vino:x:10417:10417::/home/vino:/bin/sh`, `/etc/group` with `inet:x:3003:vino`,
  `/etc/resolv.conf` (`nameserver 100.100.100.100` then `1.1.1.1`), `/etc/ssl/certs` from
  the Nix CA bundle, `/tmp` (1777), `/bin/sh` → Nix busybox or bash.

- [ ] **Step 1: Write `pong-hide-check`** and run it now, before anything exists.
  Expected: `OK hidden`.
- [ ] **Step 2: Write `pong-nix-install`.** Downloads the official Nix aarch64-linux release
  tarball from `releases.nixos.org` into a new empty temp dir, checks it against the
  `.sha256` published next to it, unpacks into `$PONG_NIX_ROOT`, creates the layout above,
  runs the tarball's single-user install inside the chroot as uid 10417. Refuses to run if
  `$PONG_NIX_ROOT` exists and is not empty.
- [ ] **Step 3: Write `pong-nix-enter`.** `su -c` → `unshare -m` with private propagation
  (toybox `unshare`; check it exists first, else KSU `su --mount-master` is not acceptable
  because it is the global namespace) → bind `/proc /dev /sys /data /sdcard /system /apex
  /linkerconfig /vendor /product` → `chroot` → drop to uid/gid 10417, groups
  `10417,3003,9997,20417,50417` → `HOME=/home/vino`, login shell.
- [ ] **Step 4: Run** `PONG_NIX_ROOT=/data/nix-root sh pong-nix-install`, then
  `pong-nix-enter nix run nixpkgs#hello`. Expected: `Hello, world!`.
- [ ] **Step 5: Check from inside:** `pong-nix-enter sh -c 'id; curl -sI https://cache.nixos.org | head -1; termux-battery-status | head -2'`.
  Expected: `uid=10417`, `HTTP/2 200`, battery JSON (Termux:API works from the chroot).
- [ ] **Step 6: Hiding:** open two sessions, close both, then `pong-hide-check` → `OK hidden`.
  Then owner runs the Play Integrity check they normally use → still STRONG, and
  `~/.claude/scripts/root-doctor.sh` output unchanged versus before Task 1.
- [ ] **Step 7: No-root path:** `PONG_SU=false pong-nix-enter true; echo $?` → prints
  `pong-nix: no root` and `2`, within 2 s.
- [ ] **Step 8: Gate.** If Step 5 or 6 fails, stop and report to the owner; do not continue.
- [ ] **Step 9: Commit** the three scripts and the spec update:
  `git commit -m "feat(pong): chroot install and entry scripts with hiding check"`

### Task 2: Repo output `homeConfigurations."vino@pong"`

**Files:**
- Modify: `lib/repository.nix` (add `phone = { system = "aarch64-linux"; username = "vino"; homeDirectory = "/home/vino"; termuxHome = "/data/data/com.termux/files/home"; };`)
- Modify: `flake.nix` (second `pkgs` for `repoConfig.phone.system`; new output)
- Create: `home/common.nix` (imports shared by laptop and phone)
- Modify: `home/default.nix` (imports `./common.nix` + desktop-only modules)
- Create: `hosts/pong/home.nix` (phone-only HM settings)
- Modify: `home/terminal/default.nix` (move `./kitty.nix` import to the laptop side)
- Modify: `home/terminal/tools.nix` (playwright-driver and the docker-compose plugin only on the laptop)

**Interfaces:**
- Produces: `homeConfigurations."vino@pong"` with `extraSpecialArgs = sharedArgs // { hostName = "pong"; }`; laptop passes `hostName = "bandit"`. Modules branch on `hostName` only where a file is shared.
- Produces: `hosts/pong/home.nix` sets `home.username`, `home.homeDirectory` from `repoConfig.phone`, `home.stateVersion = "25.11"`, the symlinks from "Decision that refines the spec" via `config.lib.file.mkOutOfStoreSymlink "${termuxHome}/<name>"`, and `programs.zsh` as login shell.

- [ ] **Step 1: Record baseline:** `nix eval --raw .#nixosConfigurations.{bandit,bandit-ci,bandit-lab}.config.system.build.toplevel.drvPath` and `.#homeConfigurations.vino.activationPackage.drvPath` into `/tmp/pong-baseline.txt`.
- [ ] **Step 2:** Make the changes above. `common.nix` = `nixvim` module, `ssh.nix`, `git.nix`, `theme.nix` (stylix colors used by zsh), `editor`, `terminal`, `node.nix`; desktop side keeps `desktop`, `qt`, `kvantum`, `xdg-*`, `dotfiles.nix`, `chromium`, `gruvbox-plus-icons`, gcr `SSH_AUTH_SOCK`. `bitwarden-cli` goes to `common.nix`.
- [ ] **Step 3: Verify laptop unchanged:** rerun Step 1's evals. Expected: identical to baseline (byte-for-byte diff empty).
- [ ] **Step 4: Verify phone evaluates:** `nix eval --raw '.#homeConfigurations."vino@pong".activationPackage.drvPath'`. Expected: a `.drv` path, system `aarch64-linux`.
- [ ] **Step 5:** `nix fmt` on changed files; run the targeted checks (`theme-contract`, `sops-isolation`) with `nix build .#checks.x86_64-linux.<name>`. A full `nix flake check` gets killed by earlyoom on the laptop; CI runs it. Expected: pass.
- [ ] **Step 6: Commit** `feat(pong): aarch64 Home Manager output sharing the laptop terminal`.

### Task 3: CI build and first activation on the phone

**Files:**
- Modify: `.github/workflows/test-nixos-config.yml` (job `pong` on `ubuntu-24.04-arm`: `nix build '.#homeConfigurations."vino@pong".activationPackage' --no-update-lock-file`, using the existing cachix step so the phone can substitute the result)
- Create: `hosts/pong/bootstrap/pong-switch` (inside chroot: `home-manager switch --flake ${termuxHome}/src/bandit-nix#vino@pong`)

- [ ] **Step 1:** Add the job. Verify locally that the YAML parses (`nix run nixpkgs#actionlint -- .github/workflows/test-nixos-config.yml`). Expected: no errors.
- [ ] **Step 2:** On the phone, clone the repo (public HTTPS) to `~/src/bandit-nix` from Termux, check out `feat/pong-host` (fetched from the laptop: `git fetch pc:src/bandit-nix-pong feat/pong-host`), run `pong-nix-enter pong-switch`. Expected: activation succeeds.
- [ ] **Step 3: Inside:** `pong-nix-enter zsh -ic 'starship --version; nvim --version | head -1; nix develop nixpkgs#hello -c hello'`. Expected: three versions/output, no errors.
- [ ] **Step 4: Review Focus 2:** in plain Termux (not the chroot): `ssh -G pc | head -1 && git config -l >/dev/null && echo ok`. Expected: `ok`; `ls -la ~ | grep -c /nix/store` → `0`.
- [ ] **Step 5: Termux hook** (rescue-safe): append to Termux `~/.zshrc` a block that, when `PONG_NIX` is unset and `~/.no-pong-nix` does not exist, runs `pong-nix-enter` and, on non-zero exit, prints `pong-nix failed, Termux shell` and continues. Back up `~/.zshrc` to `~/backups/zshrc-<date>` first. Expected: new Termux window lands in the Nix zsh; `touch ~/.no-pong-nix` gives plain Termux.
- [ ] **Step 6: Commit** `feat(pong): CI build and switch script`.

### Task 4: Secrets — age key, `secrets/pong.yaml`, keys, Bitwarden

**Files:**
- Modify: `.sops.yaml` (anchor `&host_pong`; rule `secrets/pong\.yaml` → `*user`, `*host_pong`, placed before the catch-all)
- Create: `secrets/pong.yaml` (values entered by the owner)
- Modify: `ci/sops-isolation.nix` (assert `host_pong` appears only in the `pong.yaml` rule)
- Modify: `hosts/pong/home.nix` (sops-nix HM module; `sops.age.keyFile = "/home/vino/.config/sops/age/keys.txt"`; secrets `ssh/id_pc`, `ssh/github`, `ssh/homelabKey`, `gh/token` → `~/.ssh/...` mode 0600, `GH_TOKEN` via zsh like the laptop's cachix block)
- Modify: `home/ssh.nix` (add host `pc` = `100.102.247.30` port 2222 key `~/.ssh/id_pc`, if not present on the laptop side, phone-only via `hostName`)

- [ ] **Step 1:** Inside the chroot: `age-keygen -o ~/.config/sops/age/keys.txt`; print only the public key.
- [ ] **Step 2:** Owner stores the private key file content in Bitwarden as secure note `pong age key` (owner does this; Claude never prints the private key).
- [ ] **Step 3:** Add recipient + rule; extend `ci/sops-isolation.nix`; run `nix build .#checks.x86_64-linux.sops-isolation` (or the check's actual attr). Expected: pass; then with a deliberately wrong rule (`host_pong` added to `bandit.yaml`) it fails; revert.
- [ ] **Step 4:** Owner fills `secrets/pong.yaml` with `sops secrets/pong.yaml` on the laptop (SOPS values are the owner's).
- [ ] **Step 5:** `pong-switch`; then inside: `ssh -o BatchMode=yes pc true && gh auth status && bw --version`. Expected: all succeed (Review Focus 5).
- [ ] **Step 6: Commit** `feat(pong): sops secrets for the phone` (encrypted file only).

### Task 5: Root tools in the repo and in Nix

**Files:**
- Create: `pkgs/pkt/` (copy of `~/projects/pong-kernel-tool`: `pkt/`, `tests/`, `bin/`, `README.md`, `docs/`, `requirements-telegram.txt`; not `.gitignore`d files, not any `*.session` or credentials JSON)
- Create: `pkgs/pkt/default.nix` (Python 3 application; `checkPhase` runs pytest excluding `test_real_zips.py` and `test_bootimg_real.py`)
- Create: `pkgs/pong-tools/default.nix`, `pkgs/pong-tools/boot-backup.sh`, `pkgs/pong-tools/root-doctor.sh` (copies; shebang patched to Nix bash)
- Modify: `hosts/pong/home.nix` (`home.packages` += `pkt`, `pong-tools`)

**Interfaces:**
- Produces: commands `pkt`, `boot-backup`, `root-doctor` on the chroot PATH, same CLI as today.

- [ ] **Step 1: Secret scan before copying:** `grep -rnE "api_hash|api_id|token|BEGIN .*PRIVATE" ~/projects/pong-kernel-tool --exclude-dir=.venv` and `ls` for `*.session`/`*.json`. Expected: only code that reads them from a path; nothing with values. If anything has values: stop, ask the owner.
- [ ] **Step 2:** Copy, package; `nix build .#...pkt` in CI (aarch64 job) and run `checkPhase`. Expected: tests pass.
- [ ] **Step 3: Same behavior:** run `root-doctor` in Termux and in the chroot; `diff` the outputs. Expected: no diff.
- [ ] **Step 4:** Run `boot-backup` in the chroot. Expected: `OK: /sdcard/Download/root-backups/...` and its `SHA256SUMS` equal to a Termux `boot-backup.sh` run made right before.
- [ ] **Step 5:** `pkt check <current kernel zip>` in both; expected same verdict. A real `pkt install` with the Nix build happens only at the next real kernel update with the owner's OK for that flash (not in this plan).
- [ ] **Step 6:** Point the Termux rescue `pkt` launcher at `~/src/bandit-nix/pkgs/pkt` and run `pkt --help` in plain Termux. Keep `~/projects/pong-kernel-tool` until the owner removes it.
- [ ] **Step 7: Commit** `feat(pong): pkt, boot-backup and root-doctor as packages`.

### Task 6: Claude Code inside the chroot

> **Changed 2026-11-17 (owner's OK):** no `claude-code` from nixpkgs (2.1.303, behind) and no
> `CLAUDE.md` in the public repo (it stays local, read through the `~/.claude` link). Claude Code
> comes from the official installer into the chroot's `~/.local` (as on the laptop). It needs the
> FHS loader: Home Manager links glibc's to `~/.local/lib/`, `pong-nix-root enter` links
> `/lib/ld-linux-aarch64.so.1` to it inside the chroot. Updates: `claude update` (the shared
> `~/.claude/settings.json` has `autoUpdates: false` for the Termux build).

**Files:**
- Modify: `lib/repository.nix` (add `"claude-code"` to `unfreePackageNames` if not already there)
- Modify: `hosts/pong/home.nix` (`home.packages` += `claude-code`; `~/.claude` and `~/.claude.json` symlinks already come from Task 2)
- Create: `hosts/pong/claude/CLAUDE.md` (from the phone's `~/.claude/CLAUDE.md`), linked out-of-store

- [ ] **Step 1:** Show the owner the exact `CLAUDE.md` text before committing, because the repo is public (it names hiding tools and file names). Commit only after their OK; if they decline, skip the file and keep it local.
- [ ] **Step 2:** `pong-switch`; inside: `claude --version` and `claude mcp list | grep basic-memory`. Expected: version printed, `basic-memory` connected.
- [ ] **Step 3:** In plain Termux: `claude --version` (rescue build) still works.
- [ ] **Step 4: Commit** `feat(pong): Claude Code from Nix`.

### Task 7: Remove Termux packages Nix now provides

- [ ] **Step 1:** List installed Termux packages (`pkg list-installed`), subtract the rescue kit and its dependencies (`apt-cache depends --recurse` of the kit), show the remaining list to the owner.
- [ ] **Step 2:** Only after the owner's OK: `pkg uninstall` that list.
- [ ] **Step 3:** In plain Termux (`touch ~/.no-pong-nix`, new session): `root-doctor.sh && pkt --help && ssh -G pc >/dev/null && git --version && claude --version`. Expected: all succeed. Remove `~/.no-pong-nix`.

### Task 8: Bootstrap script and restore runbook, with a drill

**Files:**
- Create: `hosts/pong/bootstrap/pong-bootstrap` (plain Termux, curl-able from `https://raw.githubusercontent.com/6FaNcY9/bandit-nix/main/hosts/pong/bootstrap/pong-bootstrap`): installs Termux packages of the rescue kit → `pong-nix-install` → `bw login` → `bw get notes "pong age key"` into the chroot's key file (mode 0600) → clone repo → `pong-switch` → Termux hook from Task 3.
- Create: `docs/runbooks/pong-restore.md`

- [ ] **Step 1: Runbook** first section "Before you need it": Bitwarden 2FA recovery code kept off this phone; Google contacts sync is on (Settings → Google → Contacts sync). Then: install Termux (GitHub build) + plugins, grant root in the KSU manager, run bootstrap; then re-login Claude and MCP tokens by hand; how to add the phone to HMA again.
- [ ] **Step 2: Drill:** `PONG_NIX_ROOT=/data/nix-root-drill sh pong-bootstrap --no-termux-hook` (bootstrap honours `PONG_NIX_ROOT` and that flag). Expected: inside the drill root, `ssh -o BatchMode=yes pc true`, `pkt --help`, `root-doctor` succeed.
- [ ] **Step 3:** Remove the drill root (`su -c rm -rf /data/nix-root-drill`, after checking the path), run `pong-hide-check` → `OK hidden`.
- [ ] **Step 4:** Add a runbook line: after any phone reboot, open Termux and confirm the Nix shell starts (Review Focus 4); owner does the reboot.
- [ ] **Step 5: Commit** `docs(pong): bootstrap and restore runbook`.
