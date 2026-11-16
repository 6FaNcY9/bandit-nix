# Phone as a Nix host (`pong`)

**Date:** 2026-11-16. **Status:** draft, written from a brainstorm on the phone; core choice
(root chroot, "B") approved by the owner; moving the phone tools into this public repo and
the permanent Termux rescue kit approved ("ok"); full document awaiting approval. Owner's words: "nix soll alles steuern", including root tooling.

## Intent

The owner's phone (Nothing Phone (2), codename Pong, rooted) is set up by hand inside
Termux today. If the phone is reset, that setup is gone. The owner wants the phone to be
a host in this repo like `bandit`: one repo describes laptop and phone, a change made for
the phone lives here, and after a reset one bootstrap brings the working environment back.

Nix should control the whole command-line environment, root tooling included. Termux stays
only as the terminal window (and for its signed plugins); it stops being where software is
installed.

Chosen approach (owner picked "B" over forking Nix-on-Droid): real Nix running in a root
chroot on the phone, not proot and not an app fork.

## Goals

After a reset, bootstrap + one Bitwarden login restores:

1. **Keys**: SSH keys (incl. `id_pc` for `ssh pc`), GitHub CLI auth, other tokens the
   phone uses today, via SOPS like `bandit`.
2. **Bitwarden** CLI with access to the vault (the root of recovery, see Secrets).
3. **Tools like on the laptop**: zsh, starship, aliases, nixvim, git, the CLI tools from
   `home/terminal` that make sense on a phone.
4. **Nix workflows**: `nix shell`, `nix develop`, `nix run`, flakes, at native speed.
5. **Root tooling**: `pkt` (`~/projects/pong-kernel-tool`), `~/.claude/scripts/boot-backup.sh`,
   `~/.claude/scripts/root-doctor.sh`, and anything they depend on, packaged by Nix and
   behaving exactly as today.
6. **Claude Code** with its config (`~/.claude`, MCP servers incl. `basic-memory`), last.
7. **Contacts** come back (outside Nix, see below).

Other apps and personal files are explicitly not in scope.

## Non-goals

- Replacing the Termux app or forking Nix-on-Droid.
- Managing Android apps, app data, or the files in `/sdcard`.
- Managing the kernel, boot partitions, KSU modules, susfs, hiding modules or their config.
- Building heavy packages on the phone (Full-LTO kernels etc. stay in CI / on a PC).

## Anti-goals (a failure even if it works)

- **Breaking hiding or integrity.** Play Integrity must stay STRONG; banking and other
  detecting apps must not be able to see `/nix`, the chroot, or new mounts. Global mounts
  visible to all apps are not acceptable.
- **Touching boot.** Nothing in this project writes `boot_a`/`boot_b`, `vendor_boot`,
  `dtbo`, `vbmeta*`, or reboots the phone.
- **Secrets in the repo** in plaintext, or ever: the TrickyStore keybox and attestation
  keys (`keybox.xml`, `tricky_store/{boot_key,hbk,keys}`, `~/kb*.xml`, `~/kb_cert*`,
  `~/cert_*.pem`) are never copied, encrypted, or committed, not even via SOPS.
- **A one-way migration.** At every phase the old Termux tool keeps working until its Nix
  replacement is verified; the owner is never left without a working root toolkit
  (needed to recover from a bad kernel flash).
- Silent changes under `/data/adb`. Any change there needs the owner's explicit OK for
  that specific change, with a backup to `/data/adb/claude_backup_<YYYYMMDD>/` first.

## Facts about the phone (checked 2026-11-16)

- Android 16, aarch64, SELinux **enforcing**. Root via KSU fork (BakaSU kernel,
  manager `com.resukisu.resukisu`); `su` gives `uid=0`, context `u:r:ksu:s0`.
- Termux is the GitHub build (testkey signature), app uid 10417, full root via its KSU
  profile. Termux:API and 6 plugins installed; they only work with Termux's signature.
- `/data` is f2fs, mounted `nosuid,nodev`; ~295 GB free.
- `uname -r`, `/proc/config.gz` and several props are spoofed for hiding; do not rely on
  them or "fix" them.
- A Google account is on the phone (contacts provider: Google Contacts).
- Root tools live in `/data/adb/ksu/bin`; `ksud` at `/data/adb/ksud`.
- Phone-side rules the owner set for agents are in `~/.claude/CLAUDE.md` on the phone; they
  reference tool paths (e.g. `~/.claude/scripts/boot-backup.sh`) that must keep working.

## How it is made (decided)

### Runtime on the phone

- A chroot root on `/data` (e.g. `/data/nix-root`) holding `/nix` and the minimum a
  glibc userland needs.
- Entering it: `su` → **private mount namespace** (so no other app sees the mounts) →
  bind mounts for `/proc`, `/dev`, `/sys`, `/data`, `/sdcard`, and whatever Android
  binaries need to keep working inside (`/system`, `/apex`, `/linkerconfig`, `/vendor`,
  …) → `chroot` → login shell from the Nix profile.
- Proot is not used. A KSU module is **not** planned; per-session namespaces should make it
  unnecessary. If the builder finds one is needed, that is an owner decision (see
  anti-goals).
- The user's home stays `/data/data/com.termux/files/home` so existing files, `~/.claude`
  and project checkouts keep working.

### In this repo

- A new host `pong` for `aarch64-linux`. `lib/repository.nix` hardcodes
  `system = "x86_64-linux"` and `flake.nix` builds one `pkgs`; both must learn a second
  system without changing what `bandit`/`bandit-lab` evaluate to.
- Shared home modules (`home/terminal`, `home/editor`, `home/git.nix`, `home/ssh.nix`, …)
  are reused; desktop-only modules (`home/desktop`, `qt`, `kvantum`, `chromium`, the gcr
  `SSH_AUTH_SOCK`) are not imported on `pong`. Splitting `home/default.nix` into shared and
  desktop parts is expected.
- Phone tools (`pkt`, `boot-backup`, `root-doctor`) become packages; their source stays in
  their own repos/paths unless moving them is clearly simpler.

### Secrets

- The phone gets its own age key; it is added as a SOPS recipient only for the secrets
  `pong` needs.
- The phone's age private key is stored in Bitwarden. After a reset: log in to Bitwarden →
  fetch age key → SOPS decrypts everything else. The Bitwarden master password is the one
  thing the owner has to know.

### Root tools and the no-root rescue kit *(Claude's calls, after the builder check)*

- Packaged root tools keep calling KSU's own binaries in `/data/adb/ksu/bin`
  (`magiskboot`, `bootctl`, `ksu_susfs`) and `/data/adb/ksud`. Nix never ships its own
  versions of these: a different `magiskboot` could repack boot images differently.
- The Nix `pkt` counts as verified when its checks pass and a dry run against an image file
  (no partition write) matches the Termux `pkt`. A real install with it happens only during
  a real kernel update, with the owner's separate OK for that flash.
- **A Termux rescue kit stays for good**: `pkt` and its Python, `boot-backup.sh`,
  `root-doctor.sh`, `openssh`, `git`, and Claude Code (Termux build). It must work without
  `su` reaching the chroot (slot B without KSU, broken manager, `CapEff=0`). Phase 5 never
  removes these. This is the one exception to "Nix controls everything", because it is how
  the owner recovers from a bad flash.
- `pkt` (`~/projects/pong-kernel-tool`), `boot-backup.sh` and `root-doctor.sh` exist only on
  the phone today (no git remote). They move into this repo (e.g. `pkgs/pong-tools/`) so a
  reset cannot lose them. This repo is **public**, so they must contain no secrets (check
  before committing).

### Claude Code config *(Claude's call)*

- In the repo: the phone's `~/.claude/CLAUDE.md`, `scripts/`, and the owner's own skills,
  linked with out-of-store symlinks (`mkOutOfStoreSymlink`) to a checkout of this repo on the
  phone, so Claude can still edit them.
- Not in the repo: credentials (Claude login, MCP tokens) are redone by hand after a reset;
  SOPS only for tokens that cannot simply be re-created.
- Auto-memory (`~/.claude/projects/*/memory/`): not declarative; the lasting facts belong in
  the shared `basic-memory` store on bandit-lab. A copy of the memory dir is part of the
  restore runbook, not of Nix.

### Bootstrap order

This repo is public, so the bootstrap script can be fetched over plain HTTPS without any
credentials. Order: Termux (GitHub build) + plugins → grant root in the KSU manager → run
the bootstrap → it sets up the chroot and Nix → Bitwarden login → age key → SOPS → Home
Manager switch.

**Bitwarden (checked 2026-11-16, server choice is Claude's assumption):** the laptop's `bw`
points at `https://bitwarden.com`, so the cloud vault is assumed; a Vaultwarden on
bandit-lab also exists. If it turns out to be Vaultwarden, the bootstrap needs the
Tailscale app logged in first. The phone holds the Bitwarden app, Bitwarden Authenticator,
Google Authenticator and Microsoft Authenticator. **Precondition the runbook must state
first:** the owner keeps the Bitwarden 2FA recovery code (or a 2FA export) somewhere off
this phone, otherwise a reset locks the vault and the whole chain breaks.

### Contacts (outside Nix)

Contacts are synced by the Google account already on the phone. The project only verifies
that contact sync is on and documents it in the restore runbook. *(Claude's call; the
owner confirmed "Kontakte" is what they meant, not how.)*

### Order (each phase verified before the next; old tool kept until then)

0. **Spike:** chroot + Nix + one `nix run nixpkgs#hello`; prove the mounts are invisible
   to apps (check from a normal app uid, e.g. `/proc/<pid>/mountinfo` of an untouched
   app); Play Integrity still STRONG; `root-doctor` still clean.
1. Shell and CLI tools from the repo via Home Manager.
2. SOPS + Bitwarden + keys; `ssh pc`, `gh` work from the Nix shell.
3. Root tools packaged; each one run in its read-only/check mode first.
4. Claude Code and its MCP servers inside the Nix environment; the Termux install stays as
   fallback until the owner says it can go.
5. Remove Termux packages that Nix now provides (keep the app, plugins, `termux-api`).
6. Bootstrap script + restore runbook; restore tested into a fresh, separate chroot dir
   (the phone itself is not reset to test it).

## Success

- In the Termux window, the owner lands in a Nix-managed shell that looks and behaves like
  the laptop's.
- `nix shell`/`nix develop` work at native speed.
- `ssh pc`, `gh`, `bw`, `pkt check`, `root-doctor` work from that shell.
- Integrity still STRONG, banking apps unaffected, nothing under boot touched.
- The restore test in a fresh chroot dir ends with the same environment.

## Left to the builder

- Exact chroot layout, which Android paths to bind, single-user Nix vs. daemon, and as
  which uid/SELinux context the shell runs (Termux:API calls must still work).
- How Termux starts the chroot shell (login script, `termux-exec` interplay).
- How the `pong` config is built and checked: native on the phone, remote builder, or an
  aarch64 GitHub Actions runner; how CI checks it.
- Whether `pong` uses standalone Home Manager or Nix-on-Droid's module system as a library.
- Package names, file layout, and how the old tool paths in the phone's CLAUDE.md keep
  working (wrappers or updated docs).
