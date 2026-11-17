#!/data/data/com.termux/files/usr/bin/bash
# Read-only root and kernel health report. Exit 1 if root is unavailable.
su -c 'id -u' 2>/dev/null | grep -qx 0 || { echo "FAIL: no root"; exit 1; }
su -c '
echo "kernel real : $(cat /proc/version | cut -d" " -f3-)" | cut -c1-90
echo "kernel shown: $(uname -r)"
echo "build       : $(getprop ro.build.display.id) patch $(getprop ro.build.version.security_patch)"
echo "slot        : $(getprop ro.boot.slot_suffix)"
echo "ksud        : $(/data/adb/ksud --version)"
echo "manager     : $(pm list packages 2>/dev/null | grep -E "resukisu|kernelsu" | cut -d: -f2 | tr "\n" " ")"
echo "boot_a      : $(sha256sum /dev/block/by-name/boot_a | cut -c1-16)"
echo "boot_b      : $(sha256sum /dev/block/by-name/boot_b | cut -c1-16)"
[ -e /data/adb/modules_update ] && [ -n "$(ls /data/adb/modules_update)" ] && echo "pending     : module updates wait for reboot: $(ls /data/adb/modules_update | tr "\n" " ")"
echo "--- modules"
for m in /data/adb/modules/*; do
  s=on; [ -e $m/disable ] && s=OFF; [ -e $m/remove ] && s=REMOVE
  printf "%-7s %-22s %s\n" "$s" "$(basename $m)" "$(grep -m1 ^version= $m/module.prop | cut -d= -f2 | cut -c1-40)"
done
echo "--- boot scripts"
ls /data/adb/post-fs-data.d /data/adb/post-mount.d /data/adb/service.d /data/adb/boot-completed.d 2>/dev/null
'
last=$(ls -d /sdcard/Download/root-backups/*/ 2>/dev/null | sort | tail -1)
echo "--- backup"
if [ -z "$last" ]; then echo "WARN: no boot backup, run boot-backup.sh"; else
  echo "latest: $last"
  cur=$(su -c "sha256sum /dev/block/by-name/boot_$(getprop ro.boot.slot_suffix | tr -d _)" | cut -d' ' -f1)
  grep -q "$cur" "$last/SHA256SUMS" && echo "active boot matches backup" || echo "WARN: active boot differs from latest backup"
fi
