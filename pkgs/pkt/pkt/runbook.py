import os

PATH = "/storage/emulated/0/Download/pkt-rescue.md"


def write_runbook(state, path=PATH, current=None, live_hash=None):
    good = state.known_good or "a"
    other = "b" if good == "a" else "a"
    img = state.known_good_image if (state.known_good_image or {}).get("slot") == good else None
    if img and live_hash:  # a kept image that is not what the slot holds is not "the one that booted"
        try:
            if live_hash(f"boot_{good}") != img.get("sha"):
                img = None
        except Exception:  # cannot check: keep naming it
            pass
    if img:
        restore = (f"2. If that is not enough, reflash the image that booted and passed the checks on slot {good}\n"
                   f"   (copy {img['path']} to your PC beforehand; sha256 {img['sha']}):\n"
                   f"   fastboot flash boot_{good} <that file>")
    else:
        restore = (f"2. If that is not enough, reflash its boot image from the backup folder:\n"
                   f"   fastboot flash boot_{good} boot_{good}.img")
    txt = f"""# pkt rescue runbook

Current slot: {current or "unknown"}
Known good slot: {good}
Backup folder: {state.last_backup or "none recorded"}

If the phone will not boot, hold power + volume down into fastboot, then:

1. Switch to the known good slot:
   fastboot --set-active={good}
{restore}
3. To repair the other slot too:
   fastboot flash boot_{other} boot_{other}.img
4. To get a working recovery without flashing:
   fastboot boot orangefox-stock-kernel-boot.img

Then restart the phone yourself. pkt never reboots.
"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(txt)
    return txt
