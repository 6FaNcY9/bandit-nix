# bandit LUKS in-place encryption runbook

Converts the existing root partition to LUKS2 **without reinstalling and
without wiping data**, using `cryptsetup reencrypt --encrypt`. Read fully
before starting.

- Time budget: 2–3 hours (mostly waiting on reencryption + one reboot window).
- Hardware needed: two USB sticks — (A) NixOS live ISO, (B) encrypted backup —
  plus the laptop on AC power. Interrupting AC during reencryption is
  recoverable (see "If something goes wrong"), but do not tempt fate.
- You must know: your current user password (unchanged — it comes from the
  sops `user-password` secret), and a new LUKS passphrase you will invent
  during conversion (use a 5–6 word diceware sentence).
- Keep a second device (phone) handy to read this guide while the laptop is on
  the live ISO. The guide lives in the repo, so it is on GitHub after step 1.

Why this works without a reinstall: `cryptsetup reencrypt --encrypt` shifts
the existing BTRFS data to make room for a 16 MiB LUKS2 header at the start of
the partition and encrypts everything in place. The **BTRFS filesystem UUID is
unchanged**, so every `fileSystems` entry in `hosts/bandit/hardware.nix` keeps
working as-is — the only config change is adding one `boot.initrd.luks` block.
The existing `@var` subvolume layout is kept.

---

## Phase 0 — prepare on the running system (~1 h)

### 1. Commit and push all pending work

```bash
cd ~/src/bandit-nix
git status
git add -A && git commit && git push
```

### 2. Verify the system is healthy

Fix regressions now, while the system is guaranteed bootable:

```bash
sudo nixos-rebuild switch --flake .#bandit
bandit-health
```

### 3. Inventory what is at risk

The whole point of in-place conversion is that nothing leaves the disk — but
treat the backup as mandatory anyway. Reencryption is journaled and resumable,
yet a bug or bad device is not worth your home directory.

| Data | Where | Covered by |
|------|-------|------------|
| Dotfiles/config | repo + Home Manager | git (step 1) |
| Secrets (github ssh keys, tokens) | `secrets/*.yaml` | git (encrypted) |
| sops age key | `/var/lib/sops-nix/key.txt` | **manual copy — step 4** |
| GPG secret key | `~/.gnupg` | **manual export — step 4** |
| Personal data | `/home/vino` | **backup — step 5** |
| VM images | `/var/lib/libvirt/images` | optional, step 5 |

### 4. Export the keys that are NOT in git

```bash
# sops age key
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

**Verify the backup:** reopen it, spot-check that `home-vino/Documents`,
`.ssh`, `.gnupg`, browser profiles etc. are readable. A backup you have not
opened is not a backup.

### 6. Shrink the BTRFS filesystem (online, safe)

The LUKS2 header needs 16 MiB; `--reduce-device-size 32M` below carves that
out of the **end** of the partition, so the filesystem must be at least 32 MiB
smaller than the partition first. BTRFS shrinks online, while running:

```bash
sudo btrfs filesystem resize -64m /
sudo btrfs filesystem show /      # dev size should now be 64 MiB below lsblk's partition size
lsblk -o NAME,SIZE /dev/nvme0n1
```

(64 MiB, not 32 — headroom costs nothing.)

### 7. Create the live USB (stick A)

Use the already-downloaded live ISO at
`~/Archive/Install-Media/ISOs/Downloads-ISOs/nixos-minimal-25.11.8107.1073dad219cb-x86_64-linux.iso`.
Minimal ISO: set up WiFi with `sudo nmtui`. Write it:

```bash
sudo dd if=nixos-*.iso of=/dev/sdY bs=4M status=progress oflag=sync   # CHECK the device!
```

---

## Phase 1 — live ISO (~30–90 min, device-speed bound)

### 8. Boot the live USB

Power on, tap `F12` (Framework boot menu), pick the USB. Plug in AC.

### 9. Connect to the network

Needed for the final rebuild step. Minimal ISO: `sudo nmtui`.

### 10. Identify the internal disk and confirm it is untouched

```bash
lsblk -o NAME,SIZE,MODEL,FSTYPE
```

Confirm the internal NVMe (usually `/dev/nvme0n1`) by the MODEL column, and
that nothing from it is mounted (`findmnt | grep nvme` → no output).

### 11. Convert the root partition to LUKS2 in place

```bash
sudo cryptsetup reencrypt --encrypt --type luks2 \
  --cipher aes-xts-plain64 --key-size 512 --pbkdf argon2id \
  --reduce-device-size 32M /dev/nvme0n1p2
```

You will be asked for the new LUKS passphrase (twice). The command shifts and
encrypts all data; progress is printed. **If interrupted** (power loss,
accidental Ctrl-C is not interrupt-safe mid-write but power loss is
journaled): reboot the live ISO and rerun the exact same command — it resumes
from the reencryption journal.

### 12. Open the container, reclaim the shrunk space, record the UUID

```bash
sudo cryptsetup open /dev/nvme0n1p2 cryptroot
sudo mount /dev/mapper/cryptroot /mnt -o subvol=@
sudo btrfs filesystem resize max /mnt      # fs grows back to fill the LUKS device
sudo cryptsetup luksUUID /dev/nvme0n1p2    # RECORD THIS — it goes into hardware.nix
sudo blkid /dev/mapper/cryptroot           # sanity: the old BTRFS UUID, unchanged
```

### 13. Add the LUKS device to hardware.nix

Still on the live ISO, edit the repo checkout inside the installed system:

```bash
$EDITOR /mnt/home/vino/src/bandit-nix/hosts/bandit/hardware.nix
```

Add (with the UUID from step 12):

```nix
boot.initrd.luks.devices."cryptroot" = {
  device = "/dev/disk/by-uuid/<LUKS-UUID>";
  allowDiscards = true; # NVMe TRIM through LUKS
};
```

Do **not** touch the `fileSystems` entries — the BTRFS UUID they reference is
unchanged and now resolves through the mapper device.

### 14. Rebuild the installed system from the live ISO

Mount the full layout so activation sees everything it expects:

```bash
sudo mount /dev/mapper/cryptroot /mnt -o subvol=@            # if not already mounted
sudo mount /dev/mapper/cryptroot /mnt/home -o subvol=@home
sudo mount /dev/mapper/cryptroot /mnt/nix -o subvol=@nix
sudo mount /dev/mapper/cryptroot /mnt/var -o subvol=@var
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo nixos-enter --root /mnt -c \
  'cd /home/vino/src/bandit-nix && nixos-rebuild boot --flake .#bandit'
```

This installs a boot entry whose initrd unlocks `cryptroot`. Nothing is
switched yet — the running system is the live ISO.

### 15. Reboot

```bash
sudo umount -R /mnt 2>/dev/null || true
sudo cryptsetup close cryptroot
reboot
```

Remove the live USB when the firmware screen appears.

---

## Phase 2 — first boot on the encrypted disk (~30 min)

### 16. Unlock and log in

Enter the LUKS passphrase at the initrd prompt, then log in as `vino` with
your usual password.

### 17. Verify and commit

```bash
bandit-health
ls /run/secrets                      # user-password, cachix-secret, etc.
test -f ~/.ssh/github && echo ssh-key-ok
sudo cryptsetup status cryptroot     # active, luks2, aes-xts-plain64
findmnt / -o SOURCE                  # /dev/mapper/cryptroot
```

```bash
cd ~/src/bandit-nix
nix run nixpkgs#alejandra -- hosts/bandit/hardware.nix
git add hosts/bandit/hardware.nix
git commit -m "feat(hosts/bandit): encrypt disk with LUKS2 in place"
git push
```

### 18. Functional smoke test

```bash
git config --global --get user.signingkey && git log --show-signature -1
sudo systemctl start tor-routing-enable && curl -s https://check.torproject.org/api/ip
sudo systemctl stop tor-routing-enable
```

No data restore is needed — nothing left the disk. Keep the backup stick
around until the setup has survived a few reboots.

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
  memory once the encrypted disk is confirmed stable.

## If something goes wrong

- **Forgot the LUKS passphrase** → no recovery. The data is gone. Choose
  carefully in step 11.
- **Reencryption interrupted** → boot the live ISO and rerun the exact
  command from step 11; it resumes from the journal. Do not run anything else
  against the partition first.
- **First boot does not reach the LUKS prompt** → boot the live USB, open the
  container (`sudo cryptsetup open /dev/nvme0n1p2 cryptroot`), mount `@`, fix
  the UUID in `hosts/bandit/hardware.nix`, rerun step 14.
- **LUKS prompt appears but boot fails afterward** → the BTRFS side is fine
  (UUID unchanged); check `subvol=` names in `fileSystems` against
  `sudo btrfs subvolume list /mnt`.
- **Want to abandon the idea entirely** → nothing on disk changed yet if you
  stop before step 11; the only leftover is the 64 MiB shrink, reverted with
  `sudo btrfs filesystem resize max /`.

## Appendix — full reinstall alternative

If the disk is ever being replaced or the layout should change to the
bandit-lab subvolume scheme (`@log` instead of `@var`), the wipe-and-reinstall
installer `script/install-bandit.sh` (gitignored, local-only) still does the
old destructive flow: erase disk, GPT with 1 GiB ESP + LUKS2 container,
generate `hardware.nix`, `nixos-install`. That path is no longer needed just
to get encryption.
