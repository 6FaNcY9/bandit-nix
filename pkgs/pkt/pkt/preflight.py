from .device import RootError

MIN_BATTERY = 30
PARTS = ("vbmeta", "dtbo", "vbmeta_system", "vendor_boot")


def preflight(dev, state, need_rehearsal=True, need_caps=True):
    """Return reasons to refuse; empty list means OK."""
    why = []
    try:
        if need_caps and not dev.caps_full():
            why.append("su lacks CAP_SYS_ADMIN/CAP_DAC_OVERRIDE (capabilities dropped)")
        if dev.device_state() != "unlocked":  # /proc/bootconfig, not the spoofed props
            why.append("bootloader is not unlocked according to /proc/bootconfig")
        if dev.battery() < MIN_BATTERY:
            why.append(f"battery below {MIN_BATTERY}%")
        if dev.merge_status() != "none":
            why.append("snapshot merge in progress or pending; wait for it to finish")
        hashes = {p: (dev.partition_hash(p + "_a"), dev.partition_hash(p + "_b")) for p in PARTS}
        fp = dev.fingerprint()
    except (RootError, ValueError, KeyError, IndexError) as e:
        return why + [f"device check failed: {e}"]
    tail = "an OTA is the likely cause; rerun the rehearsal"
    for p, (a, b) in hashes.items():
        if a != b:
            why.append(f"{p} differs between slots a and b (they hold different builds); "
                       "the rehearsal cannot run until they match")
    base = state.baseline
    if need_rehearsal and base is not None:  # a rerun must be allowed to replace a stale baseline
        for p, (a, _) in hashes.items():
            if a != base.get(p):
                why.append(f"{p} differs from baseline: {tail}")
        if fp != base.get("fingerprint"):
            why.append(f"build fingerprint differs from baseline: {tail}")
    if need_rehearsal and not state.rehearsal_passed:
        why.append("rehearsal has not passed")
    return why
