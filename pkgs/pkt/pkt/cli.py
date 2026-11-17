import asyncio
import contextlib
import dataclasses
import json
import os
import re
import shlex
import subprocess
import sys

from . import github, install as installer, postcheck, zipcheck
from .device import Device, RootError
from .rehearsal import RehearsalError, rehearse_check, rehearse_finish, rehearse_start
from .runbook import PATH as RUNBOOK, write_runbook
from .preflight import preflight
from .state import State
from .textclean import sanitize
from .bootimg import sha

BACKUP = os.path.expanduser("~/.claude/scripts/boot-backup.sh")


def getprop(k):
    try:
        return subprocess.run(["getprop", k], capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""


def backup_runner():
    r = subprocess.run([BACKUP], capture_output=True, text=True)
    lines = r.stdout.strip().splitlines()
    if r.returncode != 0 or not lines or not lines[-1].startswith("OK: "):
        raise RuntimeError("boot backup failed: " + (lines[-1] if lines else r.stderr.strip()))
    return lines[-1][4:]


def root_or(f):
    try:
        return f()
    except (RootError, KeyError, ValueError):
        return "unavailable"


def status(dev, state):
    print("slot (prop):", getprop("ro.boot.slot_suffix") or "unavailable")
    print("slot (root):", root_or(dev.current_slot))
    print("kernel:", root_or(dev.real_kernel))
    print("full capabilities:", root_or(dev.caps_full))
    print("running slot marked successful:", root_or(lambda: dev.is_successful(dev.current_slot())))
    pd = state.pending
    if pd:
        print(f"pending: stage {pd.get('stage')}, slot {pd.get('slot')}, kernel {pd.get('kernel_version')}, "
              f"image {str(pd.get('image_sha'))[:8]}")
    else:
        print("pending: none")
    print("known good:", state.known_good or "none")
    print("rehearsal passed:", state.rehearsal_passed)
    print("slot b booted at:", state.b_booted_at or "never")
    print("last backup:", state.last_backup or "none")


def candidates_path(state):
    return os.path.join(os.path.dirname(state.path), "candidates.json")


def find_cmd(dev, state):
    everything = github.find()
    running = root_or(lambda: tuple(int(x) for x in
                      re.search(r"Linux version (\d+\.\d+\.\d+)", dev.real_kernel())[1].split(".")))
    cands = everything
    if running != "unavailable":  # older kernels would be rejected by check anyway
        cands = [c for c in everything if c.version >= running]
    os.makedirs(os.path.dirname(state.path), exist_ok=True)
    with open(candidates_path(state), "w") as f:
        json.dump([dataclasses.asdict(c) for c in cands], f, indent=2)
    if not everything:
        print("no BakaSU 5.10 kernels found upstream")
    elif not cands:
        print(f"{len(everything)} found upstream, all older than the running kernel")
    for i, c in enumerate(cands, 1):
        print(f"{i}. {c.name}  [{'verified' if c.verified else 'UNVERIFIED'}, {c.source}]")


def load_candidate(state, n):
    try:
        if n < 1:
            raise IndexError
        with open(candidates_path(state)) as f:
            raw = json.load(f)[n - 1]
        raw["version"] = tuple(raw["version"])
        c = github.Candidate(**raw)
    except (OSError, ValueError, IndexError):
        raise RuntimeError("no such candidate: run pkt find first")
    except (KeyError, TypeError):
        raise RuntimeError("candidates.json is malformed: run pkt find again")
    if c.path is None and (not isinstance(c.url, str) or not c.url.startswith("https://")):
        raise RuntimeError("candidate url is not https: refusing")
    if not github.ASSET.match(str(c.name)) and c.path is None:
        raise RuntimeError("candidate name is not a BakaSU 5.10 zip name: refusing")
    return c


def known_digest(state, path):
    """True if the file's sha256 equals that of a verified candidate from the last pkt find."""
    try:
        with open(candidates_path(state)) as f:
            want = {c["sha256"] for c in json.load(f) if c.get("verified") and c.get("sha256")}
        return sha(path) in want
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        return False


def resolve(state, target, strict=False):
    """A candidate number or a path to a zip: return (path, verified).
    strict (prepare): a local path counts as unverified unless it matches a verified candidate's digest."""
    if (target.isascii() and target.isdigit()) and not os.path.exists(target):
        c = load_candidate(state, int(target))
        d = os.path.join(os.path.dirname(state.path), "downloads")
        os.makedirs(d, exist_ok=True)
        return c.path or github.download(c, d), c.verified
    return target, (known_digest(state, target) if strict else True)


def check_cmd(dev, state, target):
    path, verified = resolve(state, target)
    r = zipcheck.check_zip(path, dev, state)
    if not verified:
        r.unknowns.append("digest not verified: GitHub gave no sha256 for this file")
    print("file:", path)
    print("Image sha256:", r.image_sha or "unknown")
    for k, v in r.info.items():
        if k != "anykernel.sh":
            print(f"{k}: {v}")
    if not verified:
        print("*** UNVERIFIED DOWNLOAD: no digest to check it against ***")
    for x in r.rejects:
        print("REJECT:", x)
    for x in r.unknowns:
        print("unknown:", x)
    print("anykernel.sh (shown, never run):")
    print(sanitize(r.info.get("anykernel.sh", "(none)")))
    if not r.ok:
        print("result: rejected")
        return 1
    if r.needs_confirmation:
        names = ", ".join(x.split(":")[0] for x in r.unknowns)
        print(f"result: compatible, {len(r.unknowns)} unknown (needs confirmation): {names}")
        return 3
    print("result: compatible")
    return 0


ERRORS = (installer.InstallError, RootError, KeyError, OSError, ValueError)


def prepare_cmd(dev, state, target, flags, backup=backup_runner):
    if any(f not in ("--accept-unverified", "--accept-unknown") for f in flags):
        print("usage: pkt prepare <n|path> [--accept-unverified] [--accept-unknown]")
        return 2
    try:
        why = preflight(dev, state, need_caps=False)  # first, so a refused phone downloads nothing
        if why:
            print("error: prepare refused: " + "; ".join(why), file=sys.stderr)
            return 1
        path, verified = resolve(state, target, strict=True)
        p = installer.prepare(path, dev, state, accept_unverified="--accept-unverified" in flags,
                              accept_unknown="--accept-unknown" in flags, verified=verified, backup=backup,
                              need_caps=False)  # prepare writes nothing, so low capabilities are fine here
    except ERRORS as e:
        print("error:", e, file=sys.stderr)
        return 1
    print("file:", path)
    print("Image sha256:", p["image_sha"])
    print("kernel:", p["kernel_version"])
    for x in p["accepted_unknowns"]:
        print("accepted unknown:", x)
    if p["unverified"]:
        print("accepted: UNVERIFIED FILE")
    print(f"Prepared boot image for slot {p['slot']} (nothing written to any partition):")
    print(" ", p["image_path"])
    print("Backup folder:", p["backup"])
    print(f"  boot_{p['from_slot']}.img (running slot) sha256 {p['current_backup_sha']}")
    print(f"  boot_{p['slot']}.img (target slot)  sha256 {p['source_sha']}")
    print("Rescue runbook (written again by pkt install):", RUNBOOK)
    print("Copy the backup folder off this phone (PC or another device), then run:")
    print(f"  pkt install --confirmed-copy={installer.copy_token(p['current_backup_sha'])}")
    print("After restarting into the new kernel, run: pkt post-check")
    return 0


def install_cmd(dev, state, confirmed):
    """confirmed: the --confirmed-copy value, or None."""
    try:
        if root_or(dev.caps_full) is not True:
            # validate everything that can be validated without writing, then hand over
            cur, target, p, _ = installer.validate(dev, state, ("prepared",), need_caps=False)
            print("This shell lacks the root capabilities to write partitions, so pkt will not install.")
            print(f"Running slot {cur}; the kernel must go to boot_{target} only. Flash the prepared, verified image by hand:")
            print("  image:", p["image_path"], "(sha256", p["boot_sha"] + ")")
            print(f"  0. Kernel Flasher cannot read that private path. Copy it to /sdcard first (your own file, so")
            print(f"     no su needed): cp {shlex.quote(p['image_path'])} /sdcard/Download/")
            print(f"  1. Kernel Flasher (or the manager): flash that copy to the boot partition of slot {target}")
            print(f"     (the inactive slot), never to slot {cur}.")
            print(f"  2. Switch to slot {target} in the app, or in OrangeFox's reboot menu if bootctl fails.")
            print("  3. Restart yourself, then run: pkt post-check")
            return 1
        cur = dev.verified_slot()
        target = installer.install(dev, state, confirmed, runbook=lambda c: write_runbook(state, RUNBOOK, c, dev.partition_hash))
    except ERRORS as e:
        print("error:", e, file=sys.stderr)
        return 1
    print(f"Slot {target} written, read back and verified, and set active for the next boot.")
    print("Ready: restart your phone now. pkt never reboots.")
    print("If it does not come up:")
    print(f"  - The bootloader should fall back to slot {cur} by itself (untested here).")
    print(f"  - Otherwise hold power + volume down for fastboot: fastboot --set-active={cur}")
    print(f"  - Or boot OrangeFox and pick slot {cur.upper()} in its reboot menu.")
    print("    If the new kernel panics, OrangeFox on that slot is likely gone too: use fastboot from a PC,")
    print("    e.g. fastboot boot orangefox-stock-kernel-boot.img")
    print("  - Full steps:", RUNBOOK)
    print("After it boots, run: pkt post-check")
    return 0


def discard_cmd(dev, state):
    try:
        note = installer.discard(dev, state)
    except ERRORS as e:
        print("error:", e, file=sys.stderr)
        return 1
    print("Pending install discarded.")
    if note:
        print(note)
    return 0


def istty():
    return sys.stdin.isatty() and sys.stdout.isatty()


def crawl_cmd(args):
    limit = 2000
    if args[:1] == ["--limit"] and len(args) == 2 and args[1].isdigit():
        limit = int(args[1])
    elif args:
        print("usage: pkt crawl [--limit N]")
        return 2
    if not istty():
        print("error: pkt crawl logs in to Telegram and must be run by you in a terminal", file=sys.stderr)
        return 1
    try:
        import telethon  # noqa: F401  checked before asking for credentials
    except ImportError:
        print("error: telethon is missing: pip install -r requirements-telegram.txt", file=sys.stderr)
        return 1
    from . import crawl, tg
    try:
        creds = tg.load_credentials()
    except (OSError, ValueError) as e:
        print("error:", e, file=sys.stderr)
        return 1

    async def go():
        async with tg.session(*creds) as client:
            return await crawl.crawl(client, limit)

    try:
        result = asyncio.run(go())
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        return 130
    except Exception as e:
        print(f"error: {type(e).__name__}: {str(e)[:100]}", file=sys.stderr)
        return 1
    path = crawl.default_path()
    crawl.write_report(result, path)
    print("wrote", path)
    return 0


def post_check_cmd(dev, state):
    r = postcheck.post_check(dev, state, runbook=lambda c: write_runbook(state, RUNBOOK, c, dev.partition_hash))
    print("post-check:", r.outcome)
    for d in r.details:
        print(d)
    return 0 if r.outcome in ("good", "no_pending", "switched_back") else 1


def switch_back_cmd(dev, state):
    try:
        good, notes = postcheck.switch_back(dev, state)
    except (postcheck.PostCheckError, *ERRORS) as e:
        print("error:", e, file=sys.stderr)
        return 1
    print(f"Slot {good} (known good) is active and bootable for the next boot.")
    for n in notes:
        print(n)
    print("Restart your phone yourself now. pkt never reboots.")
    print("Then run: pkt post-check  (the other kernel is not recorded as bad after a switch-back)")
    return 0


def bad_cmd(state, f, arg, dev=None):
    try:
        sha, notes = f(state, arg, dev) if f is postcheck.mark_bad else (f(state, arg), [])
    except (postcheck.PostCheckError, *ERRORS) as e:
        print("error:", e, file=sys.stderr)
        return 1
    print(("Recorded as bad: " if f is postcheck.mark_bad else "Forgiven: ") + sha)
    for n in notes:
        print(n)
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["crawl-web"]:  # no login, so no device, state or tty needed
        from . import webcrawl
        return webcrawl.main(argv[1:])
    if argv[:1] == ["crawl"]:
        return crawl_cmd(argv[1:])
    cmd = argv[:1]
    mutating = cmd in (["prepare"], ["install"], ["discard"], ["rehearse-start"], ["rehearse-check"],
                       ["rehearse-finish"],
                       ["post-check"], ["switch-back"], ["mark-bad"], ["forgive"])
    try:
        with (State().lock() if mutating else contextlib.nullcontext()):  # lock first, then read the state
            return dispatch(Device(), State.load(), cmd, argv)
    except (RehearsalError, RootError, RuntimeError, github.GithubError, OSError, KeyError, ValueError) as e:
        print("error:", e, file=sys.stderr)
        return 1


def dispatch(dev, state, cmd, argv):
    try:
        if cmd == ["status"]:
            status(dev, state)
        elif cmd == ["find"]:
            find_cmd(dev, state)
        elif cmd == ["check"] and len(argv) == 2:
            return check_cmd(dev, state, argv[1])
        elif cmd == ["prepare"] and len(argv) >= 2:
            return prepare_cmd(dev, state, argv[1], argv[2:])
        elif cmd == ["install"] and (len(argv) == 1 or (len(argv) == 2 and argv[1].startswith("--confirmed-copy"))):
            return install_cmd(dev, state, argv[1].partition("=")[2] or None if len(argv) == 2 else None)
        elif cmd == ["discard"] and argv[1:] == ["--i-restored-the-slot"]:
            return discard_cmd(dev, state)
        elif cmd == ["post-check"] and len(argv) == 1:
            return post_check_cmd(dev, state)
        elif cmd == ["switch-back"] and len(argv) == 1:
            return switch_back_cmd(dev, state)
        elif cmd == ["mark-bad"] and len(argv) <= 2:
            return bad_cmd(state, postcheck.mark_bad, argv[1] if len(argv) == 2 else None, dev)
        elif cmd == ["forgive"] and len(argv) == 2:
            return bad_cmd(state, postcheck.forgive, argv[1])
        elif cmd == ["runbook"]:
            cur = root_or(dev.current_slot)
            write_runbook(state, RUNBOOK, None if cur == "unavailable" else cur, dev.partition_hash)
            print("wrote", RUNBOOK)
        elif cmd == ["rehearse-start"]:
            rehearse_start(dev, state, backup_runner, lambda: write_runbook(state, RUNBOOK, "a", dev.partition_hash))
            print("Backup verified and slot b set active for the next boot. Rescue runbook:", RUNBOOK)
            print("Next: restart the phone yourself. It should come up on slot b.")
            print("On slot b run: pkt rehearse-check  (no root is expected there)")
            print("Then reboot to OrangeFox, pick slot A in its reboot menu, restart,")
            print("and run: pkt rehearse-finish")
        elif cmd == ["rehearse-check"]:
            rehearse_check(state, getprop)
            print("Slot b boot recorded. Now reboot to OrangeFox, switch to slot A, restart, run pkt rehearse-finish.")
        elif cmd == ["rehearse-finish"]:
            rehearse_finish(dev, state)
            print("Rehearsal passed; baseline recorded, known good slot is a.")
        else:
            print("usage: pkt status | runbook | rehearse-start | rehearse-check | rehearse-finish | find | check <n|path> | prepare <n|path> | install --confirmed-copy=<code> | discard --i-restored-the-slot | post-check | switch-back | mark-bad [sha256] | forgive <sha-prefix> | crawl")
            return 2
    except (RehearsalError, RootError, RuntimeError, github.GithubError, OSError, KeyError) as e:
        print("error:", e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
