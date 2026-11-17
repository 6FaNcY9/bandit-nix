import dataclasses
import os
import re
import shutil

from .bootimg import sha
from .install import DEVICE_ERRORS, SLOTS, other

MIN_UPTIME = 60  # seconds: module descriptions persist on /data, so a fresh boot proves nothing
# What a healthy module says. Anything else (stale, stock, warning, crash) is a failure.
HEALTHY = {
    "rezygisk": "[Monitor: ✅, ReZygisk 64-bit: ✅, ReZygisk 32-bit: ✅]",
    "susfs4ksu": "status: ✅",
}
ALIVE = ("zygisk-ptrace64", "zygiskd64", "zygiskd32")  # `ps -A` names; the healthy description needs 32-bit too
CHECKED = "rezygisk and susfs4ksu (HMA, TrickyStore and Play Integrity Fix were NOT checked)"


class PostCheckError(RuntimeError):
    pass


@dataclasses.dataclass
class Report:
    outcome: str  # good, checks_failed, fell_back, switched_back, not_restarted, too_early, unclear, unresolved, no_pending
    details: list


def _num(slot):
    return {"a": 0, "b": 1}[slot]


def fastboot_route(slot):
    return (f"Use fastboot from a PC (hold power + volume down for the bootloader): `fastboot --set-active={slot}`. "
            "The rescue runbook has the full steps. OrangeFox's reboot menu also switches slots, but it runs on the "
            "kernel of its own slot, so a panicking kernel takes it out too; then "
            "`fastboot boot orangefox-stock-kernel-boot.img` from the PC.")


def _module_diffs(before, now):
    out = []
    for name in sorted(set(before) | set(now)):
        if name not in now:
            out.append(f"module {name} is gone (was {before[name]})")
        elif name not in before:
            out.append(f"module {name} is new ({now[name]})")
        elif before[name] != now[name]:
            out.append(f"module {name} changed: {before[name]} -> {now[name]}")
    return out


def _checks(dev, p, slot):
    """Every failed check with its reason. Empty means all passed."""
    bad = []
    try:
        kernel = dev.real_kernel().strip()  # /proc/version as root, never the spoofed uname
        want = p.get("kernel_banner")
        if not want:
            bad.append("no kernel banner was recorded at prepare, so the running kernel cannot be identified")
        elif kernel != want:
            bad.append(f"running kernel banner differs from the prepared Image's:\n      running:  {kernel}\n"
                       f"      prepared: {want}")
    except DEVICE_ERRORS as e:
        bad.append(f"cannot read the running kernel: {e}")
    try:
        live = dev.partition_hash(f"boot_{slot}")
        if live != p.get("boot_sha"):
            bad.append(f"boot_{slot} does not match the image pkt prepared (sha256 {live})")
    except DEVICE_ERRORS as e:
        bad.append(f"cannot hash boot_{slot}: {e}")
    try:
        mods = dev.modules()
        bad += _module_diffs(p.get("modules") or {}, mods)
        for m in HEALTHY:
            if mods.get(m) != "on":
                bad.append(f"module {m} is not enabled ({mods.get(m, 'not installed')})")
    except DEVICE_ERRORS as e:
        bad.append(f"cannot list modules: {e}")
    for m, want in HEALTHY.items():
        try:
            d = dev.module_description(m).strip()
        except DEVICE_ERRORS as e:
            bad.append(f"cannot read the {m} description: {e}")
            continue
        if not d.startswith(want):
            bad.append(f"{m} description is not the healthy one (must start with {want!r}): {d!r}")
    try:
        names = dev.process_names()
        bad += [f"process {n} is not running" for n in ALIVE if n not in names]
    except DEVICE_ERRORS as e:
        bad.append(f"cannot list processes: {e}")
    try:
        if not dev.susfs_answers():
            bad.append("`ksu_susfs show version` does not answer with a version")
    except DEVICE_ERRORS as e:
        bad.append(f"`ksu_susfs show version` failed: {e}")
    return bad


def record_bad(state, image_sha, reason):
    if image_sha not in state.bad_kernels:
        state.bad_kernels.append(image_sha)
    state.bad_reasons.setdefault(image_sha, reason)


def _fell_back(state, p, why):
    record_bad(state, p.get("image_sha"), why)
    state.pending = None
    state.save()
    return Report("fell_back", [why, f"Kernel {p.get('kernel_version')} (Image sha256 {p.get('image_sha')}) is recorded "
                                "as bad and pkt will refuse it (undo with `pkt forgive <sha-prefix>`). "
                                "The pending install is cleared."])


def mark_bad(state, image_sha=None, dev=None):
    """The user's own verdict. The pending kernel (no sha, or its own sha) is condemned and cleared.
    Returns (sha, notes)."""
    p = state.pending
    notes = []
    if image_sha is not None and not re.fullmatch(r"[0-9a-f]{64}", image_sha):
        raise PostCheckError("give the full 64-character Image sha256")
    if image_sha is None and not p:
        raise PostCheckError("nothing is pending: give the Image sha256 (pkt printed it) as pkt mark-bad <sha256>")
    if p and image_sha in (None, p.get("image_sha")):
        if p.get("stage") in ("writing", "write_failed"):
            raise PostCheckError(f"the install stopped at stage {p['stage']}, so boot_{p.get('slot')} may be half "
                                 "written; clearing the record would hide that. Rerun `pkt install "
                                 "--confirmed-copy=...`, or restore the slot from the backup and run "
                                 "`pkt discard --i-restored-the-slot`")
        image_sha = p.get("image_sha")
        slot = p.get("slot")
        if dev is not None and slot in SLOTS:
            try:
                if dev.active_slot() == slot:
                    notes.append(f"Slot {slot} is still the active slot: the next restart tries it again. Stop that "
                                 f"with `bootctl set-active-boot-slot {_num(other(slot))}` (root) or "
                                 f"`fastboot --set-active={other(slot)}`.")
            except DEVICE_ERRORS as e:
                notes.append(f"Could not read the active slot ({e}); check that slot {slot} is not active.")
        state.pending = None
    record_bad(state, image_sha, "marked bad by the user")
    state.save()
    return image_sha, notes


def forgive(state, prefix):
    if not re.fullmatch(r"[0-9a-f]{6,64}", prefix or ""):
        raise PostCheckError("give at least 6 hex characters of the Image sha256")
    hits = [s for s in state.bad_kernels if s.startswith(prefix)]
    if not hits:
        raise PostCheckError(f"no bad kernel starts with {prefix}")
    if len(hits) > 1:
        raise PostCheckError(f"{prefix} is ambiguous: " + ", ".join(hits))
    state.bad_kernels.remove(hits[0])
    state.bad_reasons.pop(hits[0], None)
    state.save()
    return hits[0]


def _no_root(slot, old, seen):
    d = [f"No root (slot from the prop: {seen or 'unknown'}), so no check could run and nothing was changed. "
         "The pending install is kept."]
    if seen == old:
        d.append(f"You are already on slot {old}, so this is not the new kernel: root is missing for another "
                 "reason (the manager, or su). pkt cannot judge the kernel until root works.")
    else:
        d.append(f"If this is the new kernel on slot {slot}, root is gone and pkt cannot switch slots from Android. "
                 f"Get back to slot {old}: hold power + volume down for the bootloader, then "
                 f"`fastboot --set-active={old}` from a PC, or choose slot {old.upper()} in OrangeFox's reboot menu "
                 "(OrangeFox runs on this slot's kernel, so if it will not start use "
                 "`fastboot boot orangefox-stock-kernel-boot.img` from the PC). The rescue runbook has the steps.")
    return Report("checks_failed", d)


def _keep_image(state, p, slot):
    """Copy the verified image to a place prepare does not clean, and record it. Returns a detail line."""
    dest_dir = os.path.join(os.path.dirname(state.path), "known-good")
    dest = os.path.join(dest_dir, f"boot_{slot}.img")
    try:
        os.makedirs(dest_dir, exist_ok=True)
        shutil.copyfile(p["image_path"], dest)
        if sha(dest) != p.get("boot_sha"):
            raise OSError("the copy does not match boot_sha")
    except (OSError, KeyError, TypeError) as e:
        state.known_good_image = None
        return f"Could not keep a copy of the verified image ({e}); the runbook falls back to the pre-flash backup."
    state.known_good_image = dict(slot=slot, path=dest, sha=p["boot_sha"])
    for f in os.listdir(dest_dir):  # an image kept for an earlier known good is no longer the way back
        if f != f"boot_{slot}.img":
            try:
                os.remove(os.path.join(dest_dir, f))
            except OSError:
                pass
    return (f"Kept the verified boot image for slot {slot}: {dest} (sha256 {p['boot_sha']}). The runbook names it; "
            "copy it off this phone (PC or another device).")


def post_check(dev, state, runbook=lambda current: None):
    p = state.pending
    if not p:
        return Report("no_pending", ["No install is pending, so there is nothing to check. Nothing changed."])
    slot, stage = p.get("slot"), p.get("stage")
    if slot not in SLOTS:
        raise PostCheckError(f"pending slot {slot!r} is not a or b")
    old = other(slot)
    if not dev.has_root():  # first, so nothing that needs root is read
        return _no_root(slot, old, dev.prop_slot())
    cur = dev.verified_slot()
    if stage in ("writing", "write_failed"):
        return Report("unresolved", [
            f"The install stopped at stage {stage}, so boot_{slot} may be half written. This is not a good boot.",
            f"Rerun `pkt install --confirmed-copy=...`, or restore boot_{slot} from {p.get('backup')}/boot_{slot}.img "
            "and run `pkt discard --i-restored-the-slot`."])
    if stage not in ("prepared", "written", "installed"):
        raise PostCheckError(f"unknown stage {stage!r}")
    bid = p.get("boot_id")
    if bid is None:
        return Report("unresolved", ["No boot id was recorded at prepare/install, so pkt cannot tell whether the phone "
                                     "restarted. Nothing recorded. To clear the record without a verdict on the kernel: `pkt mark-bad`, then "
                                     f"`pkt forgive {str(p.get('image_sha'))[:8]}` (the slot is checked against its backup "
                                     "by the next prepare)."])
    restarted = dev.boot_id() != bid
    if cur != slot:
        return _on_old_slot(dev, state, p, cur, slot, old, stage, restarted)
    # running on the target slot
    if not restarted:
        return Report("not_restarted", [f"The phone has not restarted since the kernel was {stage}; this boot is not "
                                        "a test of the new kernel. Nothing recorded."])
    try:
        up, done = dev.uptime(), dev.boot_completed()
    except DEVICE_ERRORS as e:
        return Report("too_early", [f"Cannot tell whether boot has finished ({e}). Nothing recorded; try again."])
    if not done or up < MIN_UPTIME:
        return Report("too_early", [f"Boot has not settled (boot_completed={'1' if done else '0'}, up {up:.0f}s, "
                                    f"need {MIN_UPTIME}s). Nothing recorded; run pkt post-check again in a minute."])
    if p.get("image_sha") in state.bad_kernels:
        return Report("checks_failed", [
            f"This kernel (Image sha256 {p.get('image_sha')}) is recorded as bad"
            f" ({state.bad_reasons.get(p.get('image_sha'), 'no reason recorded')}), so it will not be marked good. "
            f"If that was a mistake: `pkt forgive {p.get('image_sha')[:8]}`. Otherwise `pkt switch-back`."])
    active = dev.active_slot()
    if active != slot:
        return Report("checks_failed", [
            f"Slot {slot} is running but slot {active} is the active slot (after pkt switch-back, or by hand), so the "
            f"next restart leaves the new kernel. Nothing was marked good or changed. To keep slot {slot}, make it "
            f"active again (`bootctl set-active-boot-slot {_num(slot)}`) and run pkt post-check again."])
    if p.pop("switched_back", None):  # the target is active again: the earlier switch-back no longer applies
        state.save()
    route = {"prepared": "manual flash (stage prepared)",
             "written": "install saved as written: a crash before it was saved as installed",
             "installed": "normal"}[stage]
    bad = _checks(dev, p, slot)
    if bad:
        way = [f"Nothing was marked good; known good stays {state.known_good}.",
               f"Slot {old} is the way back: `pkt switch-back`, then restart yourself."]
        return Report("checks_failed", [f"Checks failed on slot {slot} ({route}):"] + ["  - " + b for b in bad] + way
                      + ["If switch-back fails: " + fastboot_route(old)])
    details = [f"Slot {slot} runs the exact prepared kernel; boot_{slot} matches; root, modules, and liveness passed.",
               f"Hiding checked: {CHECKED}."]
    state.known_good, state.pending = slot, None
    details.append(_keep_image(state, p, slot))
    state.save()
    try:
        runbook(slot)
    except OSError as e:
        details.append(f"Could not refresh the rescue runbook: {e}. Run `pkt runbook`.")
    try:
        if not dev.is_successful(slot):
            dev.mark_boot_successful()
            details.append(f"Marked slot {slot} boot successful (Android had not).")
    except DEVICE_ERRORS as e:
        details.append(f"Could not mark slot {slot} successful: {e}. Repair it as root with "
                       "`bootctl mark-boot-successful`; the next install refuses until it is.")
    try:
        ob = dev.is_bootable(old)
        state_of_old = (f"is bootable, last known working, not re-tested" if ob
                        else "is marked UNBOOTABLE")
    except DEVICE_ERRORS as e:
        state_of_old = f"could not be read ({e})"
    details.append(f"Slot {slot} is now the known good slot. Slot {old} {state_of_old}; it is the slot the next "
                   "install overwrites.")
    details.append("Check Play Integrity in your checker app; pkt cannot test it.")
    return Report("good", details)


def _on_old_slot(dev, state, p, cur, slot, old, stage, restarted):
    if stage == "prepared" and p.get("switched_back"):
        return Report("unresolved", [
            f"You switched back and slot {cur} is running. The kernel on boot_{slot} was flashed by hand and was "
            "never recorded either way. If it was bad: `pkt mark-bad`. To forget it, restore boot_"
            f"{slot} from {p.get('backup')}/boot_{slot}.img and run `pkt discard --i-restored-the-slot`; "
            f"to test it again, make slot {slot} active (`bootctl set-active-boot-slot {_num(slot)}`), restart and "
            "run pkt post-check."])
    if stage == "prepared":
        return Report("unresolved", [
            f"Running slot {cur}, but the kernel for slot {slot} is only prepared, not installed.",
            "Run `pkt install --confirmed-copy=...` first (or finish a manual flash and restart)."])
    if stage == "written":
        d = [f"Running slot {cur}; the install was saved as written, never as installed."]
        if restarted:
            d.append(f"The phone restarted since, yet slot {slot} is not running: the new kernel may have panicked "
                     "and the bootloader fallen back. If you believe it is bad, run `pkt mark-bad`; otherwise rerun "
                     "`pkt install --confirmed-copy=...`.")
        else:
            d.append("Rerun `pkt install --confirmed-copy=...` to finish it.")
        return Report("unresolved", d)
    try:
        active = dev.active_slot()
        bootable = dev.is_bootable(slot)  # a failed read is not "unbootable": record nothing
    except DEVICE_ERRORS as e:
        return Report("unclear", [f"Running slot {cur}, not the new slot {slot}, and the slot state could not be read "
                                  f"({e}). Nothing recorded; the install stays pending. Try again."])
    if not restarted:
        if active == slot:
            msg = f"You have not restarted since the install. Slot {slot} is active: restart to try it."
        else:
            msg = (f"You have not restarted since the install, and slot {active} is active, not {slot}: restarting "
                   f"will NOT test the new kernel (a switch-back or something else changed it). To test it, make "
                   f"slot {slot} active again (`bootctl set-active-boot-slot {_num(slot)}`, `pkt install` or "
                   "fastboot) and restart.")
        return Report("not_restarted", [msg + " Nothing recorded."])
    sha_ = p.get("image_sha")
    if p.get("switched_back") and bootable:  # unbootable means a real fallback, whatever else happened
        state.pending = None
        state.save()
        return Report("switched_back", [
            f"You switched back with pkt and slot {cur} is running. The new kernel was not recorded as bad.",
            f"If it was bad, run `pkt mark-bad {sha_}`. The pending install is cleared."])
    if not bootable:
        return _fell_back(state, p, f"Restarted after the install but running slot {cur}, and slot {slot} is now "
                                    "marked unbootable: the bootloader gave up on the new kernel.")
    d = [f"Restarted after the install and slot {cur} is running, but slot {slot} is still bootable. That could be a "
         "failed boot that fell back, or you chose slot " + cur + " yourself (OrangeFox, fastboot). pkt cannot tell "
         "which, so nothing was recorded and the install stays pending."]
    short = str(sha_)[:8]
    if active == slot:
        d.append(f"Slot {slot} is still active, so the next restart tries it again. To stop that: "
                 f"`bootctl set-active-boot-slot {_num(cur)}` (root) or `fastboot --set-active={cur}`.")
    else:
        d.append(f"Slot {active} is active, so a restart stays on it. To test the new kernel, make slot {slot} active: "
                 f"`bootctl set-active-boot-slot {_num(slot)}`, restart, run pkt post-check.")
    d.append("If the new kernel failed: `pkt mark-bad` (records it as bad and clears the pending install). If it was "
             f"fine and you want to stay on slot {cur}: `pkt mark-bad`, then `pkt forgive {short}` (clears the "
             "record without a verdict).")
    return Report("unclear", d)


def switch_back(dev, state):
    """Make known_good the active slot and verify it. Never reboots. Returns (slot, notes)."""
    good = state.known_good
    if good not in SLOTS:
        raise PostCheckError("no known good slot recorded, so there is nothing to switch back to")
    route = fastboot_route(good)
    try:
        cur = dev.verified_slot()
        active = dev.active_slot()
    except DEVICE_ERRORS as e:
        raise PostCheckError(f"cannot read the slots ({e}); with no root, pkt cannot switch. {route}")
    if good == cur:
        extra = (f" Slot {active} is still the active slot, though: `bootctl set-active-boot-slot {_num(cur)}` "
                 "makes this one active again." if active != cur else "")
        raise PostCheckError(f"the known good slot ({good}) is the slot you are running; there is nothing to "
                             f"switch to.{extra}")
    try:
        dev.set_active(good)
        active, bootable = dev.active_slot(), dev.is_bootable(good)
    except DEVICE_ERRORS as e:
        raise PostCheckError(f"could not make slot {good} active: {e}. {route}")
    if active != good or not bootable:
        raise PostCheckError(f"slot {good} did not become active and bootable (active reads {active}, bootable: "
                             f"{bootable}). It may be marked unbootable and bootctl did not clear that. {route}")
    notes = []
    try:
        notes.append(f"Slot {cur} (the one you are running): bootable {dev.is_bootable(cur)}, "
                     f"marked successful {dev.is_successful(cur)}.")
        notes.append(f"Slot {good}: bootable {dev.is_bootable(good)}, marked successful {dev.is_successful(good)}.")
    except DEVICE_ERRORS as e:
        notes.append(f"Could not read the slots' bootable/successful state: {e}")
    if state.pending:
        state.pending["switched_back"] = True  # so the next post-check does not condemn the kernel
        state.save()
    return good, notes
