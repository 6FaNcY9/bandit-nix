# bandit LUKS in-place encryption runbook

Converts the existing root partition to LUKS2 without reinstalling, using
`cryptsetup reencrypt --encrypt`. This modifies the only working filesystem
in place: verify an independent backup before starting.

- Time budget: 2–3 hours (mostly waiting on reencryption + one reboot window).
- Hardware needed: two USB sticks — (A) NixOS live ISO, (B) encrypted backup —
  plus the laptop on AC power. Recovery after interruption is supported,
  but does not replace a verified backup.
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

In-place encryption does not securely erase old plaintext remnants retained
by SSD wear levelling. See the upstream
[cryptsetup reencryption manual](https://gitlab.com/cryptsetup/cryptsetup/-/blob/main/man/cryptsetup-reencrypt.8.adoc)
for interruption, recovery, and device-size requirements.

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
| sops age key | `/var/lib/sops-nix/key.txt` | **manual copy — step 5** |
| GPG secret key | `~/.gnupg` | **manual export — step 5** |
| Personal data | `/home/vino` | **backup — step 5** |
| VM images | `/var/lib/libvirt/images` | optional, step 5 |

### 4. Prepare the encrypted backup drive

An unencrypted backup defeats the entire point of LUKS. Encrypt the backup
stick first (destroys the stick's contents):

```bash
sudo cryptsetup luksFormat --type luks2 /dev/sdX1        # CHECK the device with lsblk!
sudo cryptsetup open /dev/sdX1 backup
sudo mkfs.ext4 -L bandit-backup /dev/mapper/backup
sudo mount /dev/mapper/backup /mnt
```

### 5. Export recovery keys and back up `/home`

Only after the encrypted drive is mounted, export keys directly onto it:

```bash
mountpoint -q /mnt || exit 1
sudo install -d -m 0700 -o vino -g users /mnt/recovery-keys
sudo install -m 0600 /var/lib/sops-nix/key.txt /mnt/recovery-keys/age-key.txt
(umask 077; gpg --export-secret-keys --armor 4D8770567A65FE1369E2BCC1611871842A8C1619 \
  > /mnt/recovery-keys/gpg-secret-key.asc)
test -s /mnt/recovery-keys/gpg-secret-key.asc || exit 1
sudo rsync -aHAX --info=progress2 /home/vino/ /mnt/home-vino/
# optional, large: VM images
sudo rsync -aHAX --info=progress2 /var/lib/libvirt/images/ /mnt/libvirt-images/
sudo umount /mnt && sudo cryptsetup close backup
```

**Verify the backup:** reopen and mount it, compare the age-key copy with
`sudo cmp /var/lib/sops-nix/key.txt /mnt/recovery-keys/age-key.txt`, and verify
the GPG export can be imported into a temporary GPG home on the encrypted
drive. Restore representative personal files to a temporary directory there
and compare them with the originals. Check browser profiles and SSH keys,
then unmount and close the backup. Stop if any export, copy, or verification
fails. Keep this drive disconnected during conversion.

### 6. Shrink the BTRFS filesystem online

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
Write it (verify the ISO exists and select the correct USB device):

```bash
sudo dd if="$HOME/Archive/Install-Media/ISOs/Downloads-ISOs/nixos-minimal-25.11.8107.1073dad219cb-x86_64-linux.iso" of=/dev/sdY bs=4M status=progress oflag=sync
```

---

## Phase 1 — live ISO (~30–90 min, device-speed bound)

### 8. Boot the live USB

Power on, tap `F12` (Framework boot menu), pick the USB. Plug in AC.

### 9. Connect to the network

Needed for the final rebuild step. Use Ethernet or the wireless setup
instructions supplied with the ISO; do not assume `nmtui` is installed.
Confirm network access before proceeding.

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
encrypts all data; progress is printed. Ctrl-C (SIGINT) is a supported safe
interruption. To resume an interrupted conversion, use
`sudo cryptsetup reencrypt --resume-only /dev/nvme0n1p2` from the live ISO
with the filesystem unmounted. Abrupt power loss may require metadata
recovery; stop and inspect any errors instead of repeating initialization.

### 12. Open the container, reclaim the shrunk space, record the UUID

```bash
sudo cryptsetup open /dev/nvme0n1p2 cryptroot
sudo mount /dev/mapper/cryptroot /mnt -o subvol=@
sudo mount /dev/mapper/cryptroot /mnt/home -o subvol=@home
sudo mount /dev/mapper/cryptroot /mnt/nix -o subvol=@nix
sudo mount /dev/mapper/cryptroot /mnt/var -o subvol=@var
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo btrfs filesystem resize max /mnt      # fs grows back to fill the LUKS device
sudo cryptsetup luksUUID /dev/nvme0n1p2    # RECORD THIS — it goes into hardware.nix
sudo blkid /dev/mapper/cryptroot           # sanity: the old BTRFS UUID, unchanged
```

### 13. Add the LUKS device to hardware.nix

Still on the live ISO, edit the repo checkout inside the installed system:

```bash
sudo nano /mnt/home/vino/src/bandit-nix/hosts/bandit/hardware.nix
```

Inside the existing `boot.initrd = { ... };` attrset, add this with the UUID
from step 12 (do not create a second top-level `boot` attribute):

```nix
luks.devices."cryptroot" = {
  device = "/dev/disk/by-uuid/<LUKS-UUID>";
  allowDiscards = true; # NVMe TRIM through LUKS
};
```

Do **not** touch the `fileSystems` entries — the BTRFS UUID they reference is
unchanged and now resolves through the mapper device.

### 14. Rebuild the installed system from the live ISO

The full layout, including the repository on `@home`, was mounted in step 12.
Confirm those mounts before rebuilding:

```bash
findmnt -R /mnt
sudo nixos-enter --root /mnt -c \
  'cd /home/vino/src/bandit-nix && nixos-rebuild boot --flake .#bandit'
```

This installs a boot entry whose initrd unlocks `cryptroot`. Nothing is
switched yet — the running system is the live ISO.

### 15. Reboot

```bash
sudo umount -R /mnt
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
  step 5 is its prerequisite).
- Remaining roadmap: Firefox hardening, [deferred Tor support](tor-routing-deferred.md), backups to bandit-lab,
  kernel/sysctl hardening, vulnerable-lab VMs.
- Tick the boxes in `docs/SECURITY-PLAN.md` and update the pending-items
  memory once the encrypted disk is confirmed stable.

## If something goes wrong

- **Forgot the LUKS passphrase** → no recovery. The data is gone. Choose
  carefully in step 11.
- **Reencryption interrupted** → boot the live ISO and use the
  `--resume-only` command in step 11. Do not format or recreate the LUKS header.
  Stop for diagnosis if cryptsetup reports recovery errors.
- **First boot does not reach the LUKS prompt** → boot the live USB, open the
  container and mount the layout from step 12, fix the UUID in
  `hosts/bandit/hardware.nix`, then rerun step 14.
- **LUKS prompt appears but boot fails afterward** → unlocking alone does
  not verify BTRFS health. Inspect the boot error, mapper device, filesystem
  UUID and `subvol=` names before attempting repairs.
- **Want to abandon the idea entirely** → internal-disk encryption has not
  started before step 11, but the filesystem has been shrunk and the backup
  stick formatted. Revert the 64 MiB shrink with
  `sudo btrfs filesystem resize max /`.

## Appendix — full reinstall alternative

If the disk is ever being replaced or the layout should change to the
bandit-lab subvolume scheme (`@log` instead of `@var`), the wipe-and-reinstall
installer `script/install-bandit.sh` (gitignored, local-only) still does the
old destructive flow: erase disk, GPT with 1 GiB ESP + LUKS2 container,
generate `hardware.nix`, `nixos-install`. That path is no longer needed just
to get encryption.
