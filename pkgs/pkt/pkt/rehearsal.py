import datetime

from .device import RootError
from .preflight import PARTS, preflight


class RehearsalError(RuntimeError):
    pass


def rehearse_start(dev, state, backup_runner, runbook_writer=lambda: None):
    if dev.current_slot() != "a":
        raise RehearsalError("must start from slot a")
    if state.known_good not in (None, "a"):
        raise RehearsalError(f"the known good slot is {state.known_good}, not the running slot a: a rehearsal "
                             "would make slot a known good without proof. Nothing changed")
    why = preflight(dev, state, need_rehearsal=False)
    if why:
        raise RehearsalError("preflight refused: " + "; ".join(why))
    p = state.pending
    if p:
        if p.get("stage") != "prepared":
            raise RehearsalError(f"a kernel install is unresolved (stage {p.get('stage')}): finish it with pkt install, "
                                 "or restore the slot and run pkt discard, before a rehearsal")
        try:
            live = dev.partition_hash(f"boot_{p.get('slot')}")
        except (RootError, ValueError, IndexError) as e:
            raise RehearsalError(f"cannot read boot_{p.get('slot')}: {e}")
        if live != p.get("source_sha"):
            raise RehearsalError(f"boot_{p.get('slot')} is not what it was when the kernel was prepared; "
                                 "the rehearsal would boot an unknown image")
    state.last_backup = backup_runner()  # raises on failure: slot stays untouched
    try:
        runbook_writer()  # rescue sheet must exist before the slot is armed
    except OSError as e:
        raise RehearsalError(f"cannot write rescue runbook, slot not switched: {e}")
    state.b_booted_at, state.rehearsal_passed = None, False  # old boot record must not count
    state.save()
    dev.set_active("b")


def rehearse_check(state, getprop):
    if getprop("ro.boot.slot_suffix").strip() != "_b":
        raise RehearsalError("not running on slot b")
    state.b_booted_at = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    state.save()


def rehearse_finish(dev, state):
    if dev.current_slot() != "a":
        raise RehearsalError("must be on slot a")
    if not state.b_booted_at:
        raise RehearsalError("slot b boot not confirmed; run rehearse-check on slot b first")
    img = state.known_good_image
    if img:  # drop a kept image that is not what its slot holds now
        try:
            if dev.partition_hash(f"boot_{img.get('slot')}") != img.get("sha"):
                state.known_good_image = None
        except Exception:
            pass
    state.baseline = {p: dev.partition_hash(p + "_a") for p in PARTS}
    state.baseline["fingerprint"] = dev.fingerprint()
    if state.known_good in (None, "a"):  # a kernel proven on b by post-check is not undone by a rehearsal
        state.known_good = "a"
    state.rehearsal_passed = True
    state.save()
