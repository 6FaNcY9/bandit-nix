# bandit LUKS reinstall runbook

Destructive, whole-disk procedure. Read fully before starting.

- Time budget: half a day (mostly waiting on downloads).
- Hardware needed: two USB sticks — (A) NixOS live ISO, (B) encrypted backup —
  plus the laptop on AC power.
- You must know: your current user password (same after reinstall — it comes
  from the sops `user-password` secret), and a new LUKS passphrase you will
  invent during install (use a 5–6 word diceware sentence).
- Keep a second device (phone) handy to read this guide while the laptop is
  wiped. The guide lives in the repo, so it is on GitHub after step 1.

---

## Phase 0 — prepare on the current system (~1 h)

### 1. Commit and push all pending work

The reinstall clones from GitHub, so everything must be committed and pushed.

```bash
cd ~/src/bandit-nix
git status                 # expect staged: obsidian.nix, security-tools.nix, install-bandit.sh
git add -A
git commit                 # describe: obsidian module, security toolkit, LUKS installer, tor on-demand
git push
```

### 2. Activate the new config and verify it boots healthy

Catches regressions (AppArmor, wireshark group, MAC randomization, tor
on-demand) while you still have a working system to fix them in.

```bash
sudo nixos-rebuild switch --flake .#bandit
bandit-health
```

Then use the machine briefly: WiFi reconnects (router may show a "new device"
— that is the randomized MAC), Hyprland locks/unlocks, `nmap --version`,
`wireshark --version`. Note: Tor no longer autostarts —
`sudo systemctl start tor-routing-enable` pulls it in when wanted.

Log out and back in once (the new `wireshark` group membership only applies
to fresh sessions).

### 3. Inventory what leaves the disk

| Data | Where | Covered by |
|------|-------|------------|
| Dotfiles/config | repo + Home Manager | git (step 1) |
| Secrets (github ssh keys, tokens) | `secrets/*.yaml` | git (encrypted) |
| sops age key | `/var/lib/sops-nix/key.txt` | **manual copy — step 4** |
| GPG secret key | `~/.gnupg` | **manual export — step 4** |
| Personal data | `/home/vino` | **backup — step 5** |
| VM images | `/var/lib/libvirt/images` | optional, step 5 |
| NixOS itself | — | rebuilt declaratively, no backup |

### 4. Export the keys that are NOT in git

```bash
# sops age key — without this, all secrets are unreadable after reinstall
sudo cp /var/lib/sops-nix/key.txt /run/media/vino/BACKUP_USB/age-key.txt

# GPG secret key (needed for git commit signing)
gpg --export-secret-keys --armor 4D8770567A65FE1369E2BCC1611871842A8C1619 \
  > /run/media/vino/BACKUP_USB/gpg-secret-key.asc
```

### 5. Full `/home` backup to an ENCRYPTED drive

An unencrypted backup defeats the entire point of LUKS. Encrypt the backup
stick first (destroys the stick's contents):

```bash
sudo cryptsetup luksFormat --type luks2 /dev/sdX1        # CHECK the device with lsblk!
sudo cryptsetup open /dev/sdX1 backup
sudo mkfs.ext4 -L bandit-backup /dev/mapper/backup
sudo mount /dev/mapper/backup /mnt
sudo rsync -aHAX --info=progress2 /home/vino/ /mnt/home-vino/
# optional, large: VM images
sudo rsync -aHAX --info=progress2 /var/lib/libvirt/images/ /mnt/libvirt-images/
sudo umount /mnt && sudo cryptsetup close backup
```

**Verify the backup before wiping:** reopen it, spot-check that
`home-vino/Documents`, `.ssh`, `.gnupg`, browser profiles etc. are readable.
A backup you have not opened is not a backup.

### 6. Create the live USB (stick A)

Use the already-downloaded live ISO at
`~/Archive/Install-Media/ISOs/Downloads-ISOs/nixos-minimal-25.11.8107.1073dad219cb-x86_64-linux.iso`
(it is also inside the SSD backup under `home-vino/Archive/Install-Media/ISOs/`).
Minimal ISO: set up WiFi with `sudo nmtui`. Write it:

```bash
sudo dd if=nixos-*.iso of=/dev/sdY bs=4M status=progress oflag=sync   # CHECK the device!
```

---

## Phase 1 — live ISO (~1–2 h, mostly downloads)

### 7. Boot the live USB

Power on, tap `F12` (Framework boot menu), pick the USB. Plug in AC.

### 8. Connect to the network

Graphical ISO: use the tray applet. Minimal ISO: `sudo nmtui`.

### 9. Identify the internal disk

```bash
lsblk -o NAME,SIZE,MODEL
```

Confirm which device is the internal NVMe (usually `/dev/nvme0n1`). Getting
this wrong erases your backup stick instead — check the MODEL column.

### 10. Clone and run the installer

Plug in the backup/age-key USB, then:

```bash
git clone https://github.com/6FaNcY9/bandit-nix.git
cd bandit-nix
sudo ./install-bandit.sh --disk /dev/nvme0n1 --age-key /run/media/nixos/*/age-key.txt
```

The script will:

1. Ask you to type `ERASE /dev/nvme0n1`.
2. Partition: 1 GiB ESP + LUKS2 container.
3. Ask for the new LUKS passphrase (twice).
4. Generate `hosts/bandit/hardware.nix` with the new UUIDs.
5. Format BTRFS, create subvolumes, copy the age key, run `nixos-install`.

Expect several GB of downloads (ghidra, metasploit, electron, burpsuite,
wordlists). On a network failure, rerun with `--mode install` (add
`--mode mount` first if you rebooted) — never rerun the default mode unless
you intentionally want to reformat.

### 11. Preserve the generated hardware.nix

It exists only in the live environment's clone, which vanishes on reboot:

```bash
sudo cp hosts/bandit/hardware.nix /mnt/root/hardware.nix.generated
```

### 12. Reboot

```bash
sudo umount -R /mnt 2>/dev/null || true
reboot
```

Remove the live USB when the firmware screen appears.

---

## Phase 2 — first boot on the encrypted system (~1 h)

### 13. Unlock and log in

Enter the LUKS passphrase at the initrd prompt, then log in as `vino` with
your usual password (from the sops secret).

### 14. Verify secrets and health

```bash
bandit-health
ls /run/secrets                      # user-password, cachix-secret, etc.
test -f ~/.ssh/github && echo ssh-key-ok
```

If `/run/secrets` is empty, the age key did not land —
`sudo install -m 0400 age-key.txt /var/lib/sops-nix/key.txt` then
`sudo nixos-rebuild switch --flake .#bandit` (after step 15 gives you a repo).

### 15. Commit the generated hardware.nix

```bash
mkdir -p ~/src && cd ~/src
git clone git@github.com:6FaNcY9/bandit-nix.git   # sops deployed the ssh key
cd bandit-nix
sudo cp /root/hardware.nix.generated hosts/bandit/hardware.nix
sudo chown vino:users hosts/bandit/hardware.nix
nix run nixpkgs#alejandra -- hosts/bandit/hardware.nix
git add hosts/bandit/hardware.nix
git commit -m "feat(hosts/bandit): LUKS-encrypted disk layout"
git push
```

### 16. Confirm the config is a no-op

```bash
sudo nixos-rebuild switch --flake .#bandit
```

Should change nothing (the system was installed from this exact config). If
it rebuilds the world, something diverged — investigate before continuing.

### 17. Restore personal data

```bash
sudo cryptsetup open /dev/sdX1 backup && sudo mount /dev/mapper/backup /mnt
rsync -aHAX --info=progress2 /mnt/home-vino/Documents/ ~/Documents/
rsync -aHAX --info=progress2 /mnt/home-vino/Pictures/  ~/Pictures/
gpg --import /mnt/gpg-secret-key.asc            # or restore ~/.gnupg wholesale
gpg --list-secret-keys
# browser profile, VM images, other data dirs as needed
sudo umount /mnt && sudo cryptsetup close backup
```

Dotfiles are managed by Home Manager — do **not** blindly rsync config dirs
back over them; restore data, not configuration.

### 18. Functional smoke test

```bash
git config --global --get user.signingkey && git log --show-signature -1  # GPG signing
obsidian &                              # then add Kimi K3 in Copilot settings
sudo systemctl start tor-routing-enable && curl -s https://check.torproject.org/api/ip
sudo systemctl stop tor-routing-enable
wireshark &                             # capture works without root (wireshark group)
```

---

## Phase 3 — afterwards (not same day)

- **Secure Boot** via lanzaboote (SECURITY-PLAN Phase 4 — the remaining
  decision). Do this before TPM2 enrollment.
- **TPM2 unattended unlock** once Secure Boot is in place:
  `sudo systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p2`
- **SOPS PGP recipient removal** (SECURITY-PLAN — the offline GPG backup from
  step 4 is its prerequisite and now exists).
- Remaining roadmap: Firefox hardening, Tor Browser, backups to bandit-lab,
  kernel/sysctl hardening, vulnerable-lab VMs.
- Tick the boxes in `docs/SECURITY-PLAN.md` and update the pending-items
  memory once the reinstall is confirmed stable.

## If something goes wrong

- **Forgot the LUKS passphrase** → no recovery. The data is gone. Choose
  carefully in step 10.
- **Installer died mid-download** → `--mode install` (or `--mode mount` then
  `--mode install`), never a blind full rerun.
- **First boot does not reach the LUKS prompt** → boot the live USB, open the
  container (`cryptsetup open /dev/nvme0n1p2 cryptroot`), mount `@`, check
  `hosts/bandit/hardware.nix` in the clone has the right UUIDs, reinstall with
  `--mode install`.
- **Lost the generated hardware.nix** → regenerate UUIDs by hand:
  `cryptsetup luksUUID /dev/nvme0n1p2` and `blkid /dev/nvme0n1p1`, edit
  `hosts/bandit/hardware.nix` accordingly.
