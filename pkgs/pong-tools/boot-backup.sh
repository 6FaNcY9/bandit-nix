#!/data/data/com.termux/files/usr/bin/bash
# Dumps boot partitions to shared storage and verifies each copy. Only reads partitions.
set -euo pipefail
out=/sdcard/Download/root-backups/$(date +%Y%m%d-%H%M%S)-$(getprop ro.build.display.id)
free=$(df -k /sdcard | awk 'END{print $4}')
[ "$free" -gt 1048576 ] || { echo "FAIL: under 1 GiB free"; exit 1; }
mkdir -p "$out"
for p in boot recovery vendor_boot dtbo vbmeta vbmeta_system; do for s in a b; do
  d=/dev/block/by-name/${p}_$s
  # Copy through stdout: su may not see the same /sdcard mount as Termux.
  su -c "dd if=$d bs=1M 2>/dev/null" > "$out/${p}_$s.img"
  want=$(su -c "sha256sum $d" | cut -d' ' -f1)
  got=$(sha256sum "$out/${p}_$s.img" | cut -d' ' -f1)
  [ "$want" = "$got" ] || { echo "FAIL: ${p}_$s copy does not match partition"; exit 1; }
  echo "$got  ${p}_$s.img" >> "$out/SHA256SUMS"
done; done
su -c 'cat /proc/version; getprop ro.build.fingerprint; getprop ro.boot.slot_suffix; /data/adb/ksud --version; ls /data/adb/modules' > "$out/state.txt"
echo "OK: $out"
