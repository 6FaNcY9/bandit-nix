import os
import shutil
import zipfile

from .bootimg import BootImgError, build_boot, sha
from .device import RootError
from .preflight import preflight
from .zipcheck import MAX_IMAGE, READ_ERRORS, _read_image, check_zip

SLOTS = ("a", "b")
# stages from which install may be (re)run; "installed" is deliberately absent
RERUN = ("prepared", "writing", "write_failed", "written")
# stages in which prepare must not run: the slot may be half written, or the new kernel is not yet resolved
UNRESOLVED = ("writing", "write_failed", "written", "installed")
DEVICE_ERRORS = (RootError, KeyError, ValueError, IndexError, OSError)


class InstallError(RuntimeError):
    pass


def other(slot):
    return {"a": "b", "b": "a"}[slot]


def target_slot(dev, state):
    """(running, target). The running slot must be the same by bootctl and /proc/bootconfig.
    The target is never the running slot and never the known-good one."""
    try:
        cur = dev.verified_slot()
    except DEVICE_ERRORS as e:
        raise InstallError(f"cannot establish the running slot: {e}")
    if cur not in SLOTS:
        raise InstallError(f"running slot {cur!r} is not a or b")
    if state.known_good not in SLOTS:
        raise InstallError("no known good slot recorded: the rehearsal has not passed")
    target = other(cur)
    if target == state.known_good or target == cur:
        raise InstallError(f"the only other slot ({target}) is the known good slot; refusing to overwrite it. "
                           "Boot the known good slot first")
    return cur, target


def _refuse(why, what):
    if why:
        raise InstallError(f"{what} refused: " + "; ".join(why))


def backup_hash(dev, folder, slot):
    """sha256 of folder/boot_<slot>.img, which must equal the live partition."""
    path = os.path.join(folder or "", f"boot_{slot}.img")
    try:
        have, live = sha(path), dev.partition_hash(f"boot_{slot}")
    except DEVICE_ERRORS as e:
        raise InstallError(f"cannot compare the backup {path} with boot_{slot}: {e}")
    if have != live:
        raise InstallError(f"the backup {path} does not match the live boot_{slot}")
    return have


def copy_token(backup_sha):
    return backup_sha[:8]


def read_image(zip_path, expected_sha):
    """Read the member named exactly Image again and require it to be the one that was checked."""
    try:
        with zipfile.ZipFile(zip_path) as z:
            images = [i for i in z.infolist() if i.filename == "Image"]
            if len(images) != 1 or images[0].file_size > MAX_IMAGE:
                raise InstallError("the zip changed since it was checked")
            data, got = _read_image(z, images[0])
            if len(data) != images[0].file_size:
                raise InstallError("the Image is shorter than the zip declares: refusing a truncated Image")
    except READ_ERRORS as e:
        raise InstallError(f"cannot read the zip again: {e}")
    if got != expected_sha:
        raise InstallError("the zip changed since it was checked (Image hash differs); run pkt check again")
    return data


def _boot_id(dev):
    try:
        return dev.boot_id()
    except DEVICE_ERRORS:
        return None  # post-check then cannot tell restarts apart and says so


def prepare(zip_path, dev, state, accept_unverified=False, accept_unknown=False, verified=True, backup=None,
            need_caps=True):
    """Check, back up and build a boot image for the inactive slot. Writes no partition."""
    p = state.pending
    if p and p.get("stage") in UNRESOLVED:
        if p["stage"] == "installed":
            raise InstallError("a kernel was installed and is not resolved yet: restart into it and run "
                               "pkt post-check (or pkt switch-back, then restart and run pkt post-check) before "
                               "preparing another. If you are already back on the old slot: `pkt post-check` says "
                               "what it can tell; `pkt mark-bad` if the kernel failed; or make the target slot "
                               "active (`bootctl set-active-boot-slot N`) and restart to test it")
        raise InstallError(f"an install stopped at stage {p['stage']}, so boot_{p.get('slot')} may be half written "
                           f"and may be marked unbootable ({unbootable_note(p.get('slot'))}) "
                           f"Rerun pkt install --confirmed-copy=..., or restore boot_{p.get('slot')} from "
                           f"{p.get('backup')}/boot_{p.get('slot')}.img and then run pkt discard --i-restored-the-slot")
    _refuse(preflight(dev, state, need_caps=need_caps), "prepare")
    cur, slot = target_slot(dev, state)
    if p and p.get("slot") in SLOTS:  # a pending "prepared" record: the slot must still be what it was built from
        try:
            live = dev.partition_hash(f"boot_{p['slot']}")
        except DEVICE_ERRORS as e:
            raise InstallError(f"cannot read boot_{p['slot']}: {e}")
        if live != p.get("source_sha"):
            raise InstallError(f"boot_{p['slot']} is not what the earlier prepare was built from (a manual flash, or "
                               f"a change by something else). Restore it from {p.get('backup')}/boot_{p['slot']}.img "
                               "and run pkt discard --i-restored-the-slot before preparing again. Find out why the slot "
                               "changed before restoring it")
    r = check_zip(zip_path, dev, state)
    if not r.ok:
        raise InstallError("rejected: " + "; ".join(r.rejects))
    if not verified and not accept_unverified:
        raise InstallError("this file is unverified (no sha256 from GitHub to check it against); "
                           "rerun with --accept-unverified only if you trust its source")
    if r.unknowns and not accept_unknown:
        raise InstallError("these could not be verified:\n  - " + "\n  - ".join(r.unknowns)
                           + "\nrerun with --accept-unknown if you accept them")
    data = read_image(zip_path, r.image_sha)
    if backup is None:
        raise InstallError("no backup runner")
    try:
        state.last_backup = backup()  # raises if the backup did not verify
    except RuntimeError as e:
        raise InstallError(str(e))
    state.save()
    cur_sha = backup_hash(dev, state.last_backup, cur)
    src = os.path.join(state.last_backup, f"boot_{slot}.img")

    base = os.path.dirname(state.path)
    work, keep = os.path.join(base, "work"), os.path.join(base, "images")
    for d in (work, keep):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
    # work from a private copy of the backup, so shared storage cannot change it under us
    src_copy = os.path.join(keep, f"source-boot_{slot}.img")
    try:
        shutil.copyfile(src, src_copy)
        src_sha, live = sha(src_copy), dev.partition_hash(f"boot_{slot}")
    except DEVICE_ERRORS as e:
        raise InstallError(f"cannot compare the backup with boot_{slot}: {e}")
    if src_sha != live:
        raise InstallError(f"the backup's boot_{slot}.img does not match the live boot_{slot}; nothing built")
    image = os.path.join(work, "Image")
    with open(image, "wb") as f:
        f.write(data)
    mb = os.path.join(work, "magiskboot")
    try:
        dev.fetch_magiskboot(mb)
        built = build_boot(image, src_copy, work, mb)
        new = os.path.join(keep, f"new-boot_{slot}.img")
        os.replace(built, new)  # kept outside work/: a retry must always find the good image
    except (BootImgError, *DEVICE_ERRORS) as e:
        raise InstallError(f"cannot build the boot image: {e}")
    state.pending = dict(
        slot=slot, from_slot=cur, image_path=new, boot_sha=sha(new), size=os.path.getsize(new),
        source_sha=src_sha, source_copy=src_copy, backup=state.last_backup, current_backup_sha=cur_sha,
        kernel_version=r.info.get("version"), kernel_banner=r.info.get("banner"), boot_id=_boot_id(dev), image_sha=r.image_sha, source=zip_path,
        accepted_unknowns=list(r.unknowns), unverified=not verified,
        modules=dev.modules(), stage="prepared")
    state.save()
    return state.pending


def validate(dev, state, stages, need_caps=True):
    """Every read-only check shared by install and the manual route. Returns (cur, target, pending, sha of the running slot's backup)."""
    p = state.pending
    if not p:
        raise InstallError("nothing prepared: run pkt prepare first")
    if p.get("stage") not in stages:
        raise InstallError(f"the prepared kernel is at stage {p.get('stage')!r}; this step needs {' or '.join(stages)}")
    slot = p.get("slot")
    if slot not in SLOTS:
        raise InstallError(f"prepared slot {slot!r} is not a or b")
    _refuse(preflight(dev, state, need_caps=need_caps), "install")
    cur, target = target_slot(dev, state)
    if slot != target:
        raise InstallError(f"prepared for slot {slot} but the only allowed target is {target} "
                           f"(running {cur}, known good {state.known_good})")
    if p.get("image_sha") in state.bad_kernels:
        raise InstallError("this kernel is recorded as bad")
    path, want, size = p.get("image_path"), p.get("boot_sha"), p.get("size")
    try:
        have, real_size = sha(path), os.path.getsize(path)
    except (OSError, TypeError) as e:
        raise InstallError(f"cannot read the prepared image: {e}")
    if have != want or real_size != size:
        raise InstallError("the prepared boot image on disk no longer matches what was prepared")
    if size > MAX_IMAGE:
        raise InstallError(f"image is {size} bytes, over the {MAX_IMAGE} limit")
    try:
        part_size = dev.partition_size(f"boot_{target}")
    except DEVICE_ERRORS as e:
        raise InstallError(f"cannot read the size of boot_{target}: {e}")
    if size != part_size:
        raise InstallError(f"image is {size} bytes but boot_{target} is {part_size}: they must be equal")
    cur_sha = backup_hash(dev, p.get("backup"), cur)  # the way back must exist and be current
    if p["stage"] == "prepared":  # after an attempt the partition has legitimately changed
        try:
            live = dev.partition_hash(f"boot_{target}")
        except DEVICE_ERRORS as e:
            raise InstallError(f"cannot read boot_{target}: {e}")
        if live != p.get("source_sha"):
            raise InstallError(f"boot_{target} is not what it was at prepare time. It may have been flashed by "
                               "another tool (for example by hand in Kernel Flasher), or changed by an update. "
                               "Find out which before doing anything else")
    return cur, target, p, cur_sha


def unbootable_note(slot):
    n = {"a": 0, "b": 1}.get(slot, "?")
    return (f"Slot {slot} is marked unbootable, so automatic fallback to it is off until it is made active again: "
            f"`bootctl set-active-boot-slot {n}` (root) or `fastboot --set-active={slot}` clears it.")


def _active_note(dev):
    try:
        return f"slot {dev.active_slot()} is active now (read just now)"
    except DEVICE_ERRORS:
        return "the active slot could not be read: check it before restarting"


def install(dev, state, confirmed_copy, runbook=lambda current: None):
    """Write the prepared image to the inactive slot, read it back, and only then make it active."""
    cur, target, p, cur_sha = validate(dev, state, RERUN)
    token = copy_token(cur_sha)
    if confirmed_copy != token:
        raise InstallError(f"refused: copy {p.get('backup')} (at least boot_{cur}.img) off this phone, then pass "
                           f"--confirmed-copy={token}")
    path, want, size = p["image_path"], p["boot_sha"], p["size"]
    try:
        active = dev.active_slot()
    except DEVICE_ERRORS as e:
        raise InstallError(f"cannot read the active slot: {e}")
    armed = p["stage"] == "written" and active == target  # a crash after set_active: only verify
    # "nothing written" is only true on a first attempt; after an earlier one the slot may be partly written
    nothing = " Nothing written." if p["stage"] == "prepared" else (
        f" This run wrote nothing, but an earlier attempt may have left boot_{target} partly written.")
    if active != cur and not armed:
        raise InstallError(f"the active slot is {active} but the running slot is {cur}: the other slot is already "
                           f"armed or the state is unclear.{nothing}")
    try:
        if not dev.is_successful(cur):
            raise InstallError(f"slot {cur} is not marked successful, so there would be no safe fallback. Repair it as root "
                               f"with `bootctl mark-boot-successful` (only if this slot really boots fine), then rerun.{nothing}")
        runbook(cur)  # the rescue sheet must be fresh before anything is written
    except OSError as e:
        raise InstallError(f"cannot write the rescue runbook: {e}.{nothing}")

    def err(msg):  # after the target was marked unbootable, every failure says so
        return InstallError(msg if armed else f"{msg} {unbootable_note(target)}")

    def failed(what):
        p["stage"] = "write_failed"
        state.save()
        try:
            now = dev.active_slot()  # a fresh read decides what to say
        except DEVICE_ERRORS:
            now = None
        if now == target:
            n = {"a": 0, "b": 1}[cur]
            raise InstallError(f"boot_{target} does not verify ({what}) and slot {target} IS the active slot. "
                               f"Make the running slot active again now: `bootctl set-active-boot-slot {n}` "
                               f"(or `pkt switch-back`), then rerun pkt install to rewrite it from "
                               f"{path}, or restore it from {p.get('backup')}/boot_{target}.img")
        raise err(f"boot_{target} may be partly written and was NOT activated ({what}); {_active_note(dev)}. "
                  f"Rerun pkt install to rewrite it from {path}, or restore it from "
                  f"{p.get('backup')}/boot_{target}.img.")

    if p["stage"] != "written":
        try:
            dev.set_unbootable(target)  # a half-written slot must not be bootable
        except DEVICE_ERRORS as e:
            raise InstallError(f"cannot mark slot {target} unbootable, so nothing was written: {e}")  # not marked
        p["stage"] = "writing"  # saved first: a crash from here on is visible on the next run
        state.save()
        try:
            dev.write_boot(target, path)
            dev.flush_boot(target)  # the read-back below must come from the flash, not the page cache
            got = dev.boot_prefix_hash(target, size)
        except DEVICE_ERRORS as e:
            failed(f"writing, flushing or reading back failed: {e}")
        if got != want:
            failed("the read-back hash does not match the image")
        p["stage"] = "written"
        state.save()
    else:
        try:
            got = dev.boot_prefix_hash(target, size)
        except DEVICE_ERRORS as e:
            failed(f"cannot read back: {e}")
        if got != want:
            failed("the slot no longer matches the image")

    if not armed:
        try:  # the running slot must not have been touched by any of this
            untouched = dev.partition_hash(f"boot_{cur}") == cur_sha
        except DEVICE_ERRORS as e:
            failed(f"cannot confirm the running slot's boot_{cur} is untouched: {e}")
        if not untouched:
            failed(f"boot_{cur}, the RUNNING slot, changed during the install; restore it from the backup first")
        try:
            merge = dev.merge_status()
            if merge != "none":
                raise err(f"snapshot merge status is {merge!r}; boot_{target} is written and verified but "
                          f"NOT activated; {_active_note(dev)}. Rerun pkt install when it is none.")
            if not dev.is_successful(cur):
                raise err(f"slot {cur} is no longer marked successful; boot_{target} is written but NOT "
                          f"activated; {_active_note(dev)}. Repair it as root with `bootctl mark-boot-successful` "
                          "(only if this slot really boots fine), then rerun pkt install.")
            dev.set_active(target)
        except DEVICE_ERRORS as e:
            raise err(f"boot_{target} is written and verified but activating slot {target} failed: {e}; "
                      f"{_active_note(dev)}. Rerun pkt install.")
    try:
        now, bootable = dev.active_slot(), dev.is_bootable(target)
    except DEVICE_ERRORS as e:
        raise err(f"boot_{target} is written and verified; activation could not be confirmed: {e}.")
    if now != target or not bootable:
        raise err(f"boot_{target} is written and verified but activation did not take: active slot reads "
                  f"{now}, slot {target} bootable: {bootable}. Rerun pkt install.")
    p["stage"] = "installed"
    p["boot_id"] = _boot_id(dev) or p.get("boot_id")  # a failed read must not erase the prepare id; post-check: the same id means the phone has not restarted since
    state.save()
    return target


def discard(dev, state):
    """Forget an unresolved install once the slot is back to what the backup holds."""
    p = state.pending
    if not p:
        raise InstallError("nothing to discard")
    slot = p.get("slot")
    if slot not in SLOTS:
        raise InstallError(f"pending slot {slot!r} is not a or b")
    try:
        dev.flush_boot(slot)  # a hand restore must be judged from the flash, not the page cache
        live = dev.partition_hash(f"boot_{slot}")
        active = dev.active_slot()
    except DEVICE_ERRORS as e:
        raise InstallError(f"cannot check boot_{slot}: {e}")
    if live != p.get("source_sha"):
        raise InstallError(f"boot_{slot} does not match the backup it was prepared from "
                           f"({p.get('backup')}/boot_{slot}.img); restore it first. Not discarded")
    if active == slot:
        raise InstallError(f"slot {slot} is still the active slot; make the other slot active first. Not discarded")
    stage = p.get("stage")
    state.pending = None
    state.save()
    if stage == "prepared":
        return ""
    return unbootable_note(slot) + " pkt did not clear that; do it yourself if you need the fallback."
