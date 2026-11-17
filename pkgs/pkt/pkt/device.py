import os
import re
import shlex
import subprocess

BOOTCTL = "/data/adb/ksu/bin/bootctl"
MAGISKBOOT = "/data/adb/ksu/bin/magiskboot"
KSUD = "/data/adb/ksud"
SUSFS_BIN = "/data/adb/ksu/bin/ksu_susfs"
SUSFS_PROP = "/data/adb/modules/susfs4ksu/module.prop"
CAP_DAC_OVERRIDE, CAP_SYS_ADMIN = 1, 21
BOOTCTL_FALSE = 70  # bootctl is-slot-* exit code for "no" (EX_SOFTWARE, seen on this phone)


class RootError(RuntimeError):
    def __init__(self, msg, returncode=None):
        super().__init__(msg)
        self.returncode = returncode  # the command's exit code, or None when it never ran


class Device:
    def root(self, cmd):
        # No Python-side timeout: su runs as uid 0, so the Termux uid cannot kill it and waiting would hang anyway.
        # Long commands carry their own `timeout N` inside the command, which runs as root.
        try:
            r = subprocess.run(["su", "-c", cmd], capture_output=True, text=True)
        except OSError as e:
            raise RootError(f"cannot run su: {e}")
        if r.returncode == 124:
            raise RootError(f"{cmd!r} timed out (stopped by `timeout`, rc 124)", 124)
        if r.returncode != 0:
            raise RootError(f"{cmd!r} failed ({r.returncode}): {r.stderr.strip()}", r.returncode)
        return r.stdout

    def caps_full(self):
        line = self.root("grep CapEff /proc/self/status")
        eff = int(line.split(":")[1].strip(), 16)
        return all(eff >> b & 1 for b in (CAP_SYS_ADMIN, CAP_DAC_OVERRIDE))

    def current_slot(self):
        return {"0": "a", "1": "b"}[self.root(f"{BOOTCTL} get-current-slot").strip()]

    def set_active(self, slot):
        n = {"a": "0", "b": "1"}[slot]
        self.root(f"{BOOTCTL} set-active-boot-slot {n}")

    def has_root(self):
        try:
            return self.root("id -u").strip() == "0"
        except RootError:
            return False

    def prop_slot(self):
        """Slot from the ro.boot.slot_suffix prop: needs no root, so it is the only slot read when root is missing."""
        r = subprocess.run(["getprop", "ro.boot.slot_suffix"], capture_output=True, text=True)
        return r.stdout.strip().lstrip("_") or None

    def uptime(self):
        """Seconds since boot, from /proc/uptime."""
        return float(self._first(self.root("cat /proc/uptime"), "/proc/uptime"))

    def boot_id(self):
        """Changes on every boot; /proc/sys/kernel/random/boot_id."""
        return self._first(self.root("cat /proc/sys/kernel/random/boot_id"), "boot_id")

    def boot_completed(self):
        return self.root("getprop sys.boot_completed").strip() == "1"

    def process_names(self):
        out = self.root("ps -A -o NAME")
        names = {l.strip() for l in out.splitlines()[1:] if l.strip()}
        if not names:
            raise RootError("ps listed no processes")
        return names

    def susfs_answers(self):
        """True when `ksu_susfs show version` answers with a version."""
        return bool(re.match(r"v\d+\.\d+\.\d+", self.root(f"{SUSFS_BIN} show version").strip()))

    @staticmethod
    def _first(out, what):
        words = out.split()
        if not words:
            raise RootError(f"empty output reading {what}")
        return words[0]

    def module_description(self, name):
        return self._match(r"^description=(.*)$", self.root(f"cat /data/adb/modules/{shlex.quote(name)}/module.prop"), re.M)

    def mark_boot_successful(self):
        self.root(f"{BOOTCTL} mark-boot-successful")

    def real_kernel(self):
        return self.root("cat /proc/version").strip()

    @staticmethod
    def _match(pattern, text, flags=0):
        m = re.search(pattern, text, flags)
        if not m:
            raise ValueError(f"no match for {pattern!r}")
        return m[1]

    def ksud_version(self):
        return self.root(f"{KSUD} --version")

    def ksud_uapi(self):
        return int(self._match(r"uapi: (\d+)", self.ksud_version()))

    def susfs_version(self):
        return self._match(r"^version=(\S+)", self.root(f"cat {SUSFS_PROP}"), re.M)

    def running_image_sha(self):
        # GKI boot header v4: "ANDROID!" magic, kernel_size u32 at offset 8, header_version u32 at 40,
        # and the kernel starts at the 4096-byte page 1.
        dev = f"/dev/block/by-name/boot_{self.current_slot()}"
        out = self.root(
            f"dd if={dev} bs=1 count=44 2>/dev/null | od -An -v -tx1 | tr -d ' \\n'; echo; "
            f"S=$(dd if={dev} bs=1 skip=8 count=4 2>/dev/null | od -An -tu4 | tr -d ' '); "
            f"head -c $((4096+S)) {dev} | tail -c +4097 | sha256sum").split()
        if len(out) != 3:
            raise ValueError("unexpected output reading the boot header")
        header = bytes.fromhex(out[0])
        if header[:8] != b"ANDROID!" or int.from_bytes(header[40:44], "little") != 4:
            raise ValueError("boot partition is not an Android boot image header v4")
        return out[1]

    def partition_hash(self, name):
        return self._first(self.root(f"sha256sum /dev/block/by-name/{name}"), f"the hash of {name}")

    def merge_status(self):
        return self.root(f"{BOOTCTL} get-snapshot-merge-status").strip()

    def battery(self):
        return int(self.root("cat /sys/class/power_supply/battery/capacity"))

    def fingerprint(self):
        return self.root("getprop ro.build.fingerprint").strip()

    def modules(self):
        out = self.root(
            "for d in /data/adb/modules/*/; do [ -d \"$d\" ] || continue; "
            "if [ -e \"$d/remove\" ]; then s=REMOVE; elif [ -e \"$d/disable\" ]; then s=OFF; else s=on; fi; "
            "echo \"$(basename \"$d\") $s\"; done")
        return dict(l.split() for l in out.splitlines() if l.strip())

    # --- boot partition access for install. Slots are validated here as well as in install.py. ---

    @staticmethod
    def _boot_dev(slot):
        if slot not in ("a", "b"):
            raise ValueError(f"bad slot {slot!r}")
        return f"/dev/block/by-name/boot_{slot}"

    @staticmethod
    def _num(slot):
        if slot not in ("a", "b"):
            raise ValueError(f"bad slot {slot!r}")
        return {"a": "0", "b": "1"}[slot]

    def bootconfig(self, key):
        """A value from /proc/bootconfig (not the spoofed props)."""
        return self._match(r'^' + re.escape(key) + r'\s*=\s*"([^"]*)"', self.root("cat /proc/bootconfig"), re.M)

    def verified_slot(self):
        """The running slot, which bootctl and /proc/bootconfig must agree on."""
        a = self.current_slot()
        b = self.bootconfig("androidboot.slot_suffix")
        if b != "_" + a:
            raise ValueError(f"bootctl says slot {a} but /proc/bootconfig says {b!r}")
        return a

    def device_state(self):
        return self.bootconfig("androidboot.vbmeta.device_state")

    def active_slot(self):
        return {"0": "a", "1": "b"}[self.root(f"{BOOTCTL} get-active-boot-slot").strip()]

    def _bootctl_true(self, sub, slot):
        """True on rc 0, False on bootctl's "no" (rc 70). Any other failure raises: it is not an answer."""
        try:
            self.root(f"{BOOTCTL} {sub} {self._num(slot)}")
        except RootError as e:
            if e.returncode == BOOTCTL_FALSE:
                return False
            raise
        return True

    def is_bootable(self, slot):
        return self._bootctl_true("is-slot-bootable", slot)

    def is_successful(self, slot):
        return self._bootctl_true("is-slot-marked-successful", slot)

    def set_unbootable(self, slot):
        self.root(f"{BOOTCTL} set-slot-as-unbootable {self._num(slot)}")

    def partition_size(self, name):
        return int(self.root(f"blockdev --getsize64 {shlex.quote('/dev/block/by-name/' + name)}").strip())

    def boot_prefix_hash(self, slot, length):
        """sha256 of the first `length` bytes of boot_<slot>."""
        out = self.root(f"head -c {int(length)} {self._boot_dev(slot)} | sha256sum")
        return self._first(out, f"the hash of boot_{slot}")

    def write_boot(self, slot, path):
        d = self._boot_dev(slot)
        self.root(f"test -b {d} && timeout -k 30 600 dd if={shlex.quote(path)} of={d} bs=1M conv=notrunc,nocreat,fsync")

    def flush_boot(self, slot):
        d = self._boot_dev(slot)
        self.root(f"timeout -k 30 600 sync && timeout -k 30 600 blockdev --flushbufs {d}")

    def fetch_magiskboot(self, dst):
        """Copy magiskboot out of /data/adb (a read, as root) so it can run as the Termux user."""
        try:
            with open(dst, "wb") as f:
                r = subprocess.run(["su", "-c", f"cat {MAGISKBOOT}"], stdout=f, stderr=subprocess.PIPE)
        except OSError as e:
            raise RootError(f"cannot copy magiskboot: {e}")
        if r.returncode != 0:
            raise RootError(f"cannot copy magiskboot: {r.stderr.decode(errors='replace').strip()}")
        os.chmod(dst, 0o700)
