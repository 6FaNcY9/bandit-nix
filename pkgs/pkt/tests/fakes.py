from pkt.device import Device, RootError


class FakeDevice(Device):
    """answers maps exact root command -> output; unknown commands raise RootError."""

    def __init__(self, answers):
        self.answers = answers
        self.calls = []

    def root(self, cmd):
        self.calls.append(cmd)
        if cmd not in self.answers:
            raise RootError(f"unexpected: {cmd}")
        return self.answers[cmd]


def good_answers(**over):
    h = "ab" * 32
    a = {
        "grep CapEff /proc/self/status": "CapEff:\t000001ffffffffff\n",
        "cat /sys/class/power_supply/battery/capacity": "80\n",
        "/data/adb/ksu/bin/bootctl get-snapshot-merge-status": "none\n",
        "getprop ro.build.fingerprint": "Nothing/Pong/fp:16\n",
        "cat /proc/bootconfig": 'androidboot.vbmeta.device_state = "unlocked"\nandroidboot.slot_suffix = "_a"\n',
    }
    for p in ("vbmeta", "dtbo", "vbmeta_system", "vendor_boot"):
        for s in "ab":
            a[f"sha256sum /dev/block/by-name/{p}_{s}"] = f"{h}  /dev/block/x\n"
    a.update(over)
    return a


GOOD_BASELINE = {"vbmeta": "ab" * 32, "dtbo": "ab" * 32, "vbmeta_system": "ab" * 32, "vendor_boot": "ab" * 32,
                 "fingerprint": "Nothing/Pong/fp:16"}
