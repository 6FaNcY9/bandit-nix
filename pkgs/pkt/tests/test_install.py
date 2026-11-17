import contextlib
import hashlib
import io
import json
import os
import re
import subprocess
import tempfile
import unittest
import zipfile
from unittest import mock

from pkt import bootimg, cli, install
from pkt.device import Device, RootError
from pkt.state import State
from tests.fakes import GOOD_BASELINE
from tests.test_zipcheck import Dev, image

NEW = b"NEWBOOT" * 1000
SRC = b"SOURCE-BOOT-B".ljust(len(NEW), b"\0")
RUN = b"A-RUNNING".ljust(len(NEW), b"\0")
sha = lambda b: hashlib.sha256(b).hexdigest()
TOKEN = sha(RUN)[:8]


class InstDev(Dev):
    """Zip-check answers plus an in-memory boot_a/boot_b and bootctl state.
    root() always raises: nothing real is touched."""

    def __init__(self, current="a", caps=True, **kw):
        super().__init__(**kw)
        self.current, self.caps, self.events = current, caps, []
        self.active = current
        self.part = {"a": RUN, "b": SRC}
        self.size = len(NEW)
        self.write_fails = self.short_write = self.corrupt = self.flush_fails = False
        self.activate_fails = self.unbootable_fails = False
        self.successful = {"a": True, "b": False}
        self.bootable = {"a": True, "b": True}
        self.merge = "none"
        self.activation_ignored = False

    def root(self, cmd, timeout=None):
        raise RootError("no real su in tests: " + cmd)

    def caps_full(self): return self.caps
    def battery(self): return 80
    def merge_status(self): return self.merge
    def fingerprint(self): return "Nothing/Pong/fp:16"
    def verified_slot(self): return self.current
    def current_slot(self): return self.current
    def device_state(self): return "unlocked"
    def modules(self): return {"susfs4ksu": "on"}
    def partition_size(self, name): return self.size
    def active_slot(self): return self.active
    def is_successful(self, slot): return self.successful[slot]
    def is_bootable(self, slot): return self.bootable[slot]

    def set_unbootable(self, slot):
        self.events.append(("unbootable", slot))
        if self.unbootable_fails:
            raise RootError("bootctl failed")
        self.bootable[slot] = False

    def partition_hash(self, name):
        if name.startswith("boot_"):
            return sha(self.part[name[5:]])
        return "ab" * 32

    def fetch_magiskboot(self, dst):
        open(dst, "w").close()

    def write_boot(self, slot, path):
        self.events.append(("write", slot))
        if self.write_fails:
            raise RootError("dd failed")
        with open(path, "rb") as f:
            data = f.read()
        if self.short_write:
            data = data[:len(data) // 2]
        if self.corrupt:
            data = b"X" + data[1:]
        self.part[slot] = data + self.part[slot][len(data):]

    def flush_boot(self, slot):
        self.events.append(("flush", slot))
        if self.flush_fails:
            raise RootError("sync failed")

    def boot_prefix_hash(self, slot, length):
        self.events.append(("readback", slot))
        return sha(self.part[slot][:length])

    def set_active(self, slot):
        self.events.append(("set_active", slot))
        if self.activate_fails:
            raise RootError("bootctl failed")
        if not self.activation_ignored:
            self.active = slot
            self.bootable[slot] = True


def fake_build(image_path, source_boot, workdir, magiskboot):
    os.makedirs(workdir, exist_ok=True)
    out = os.path.join(workdir, "new-boot.img")
    with open(out, "wb") as f:
        f.write(NEW)
    return out


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        t = self.tmp.name
        self.state = State(path=os.path.join(t, "state", "state.json"), known_good="a", rehearsal_passed=True,
                           baseline=dict(GOOD_BASELINE))
        self.backup_dir = os.path.join(t, "backup")
        os.makedirs(self.backup_dir)
        for s, data in (("a", RUN), ("b", SRC)):
            with open(os.path.join(self.backup_dir, f"boot_{s}.img"), "wb") as f:
                f.write(data)
        self.zip = os.path.join(t, "k.zip")
        with zipfile.ZipFile(self.zip, "w") as z:
            z.writestr("Image", image())
        self.dev = InstDev()
        self.backups = 0
        p = mock.patch("pkt.install.build_boot", fake_build)
        p.start()
        self.addCleanup(p.stop)

    def backup(self):
        self.backups += 1
        return self.backup_dir

    def prep(self, dev=None, **kw):
        kw.setdefault("accept_unknown", True)
        return install.prepare(self.zip, dev or self.dev, self.state, backup=self.backup, **kw)

    def ready(self, **over):
        self.prep()
        self.state.pending.update(over)

    def inst(self, confirmed=TOKEN, dev=None):
        return install.install(dev or self.dev, self.state, confirmed, runbook=lambda cur: None)

    def stage(self):
        return State.load(self.state.path).pending["stage"]


class Prepare(Base):
    def test_prepare_writes_no_partition(self):
        before = dict(self.dev.part)
        p = self.prep()
        self.assertEqual(self.dev.events, [])
        self.assertEqual(self.dev.part, before)
        self.assertEqual(p["stage"], "prepared")
        self.assertEqual(p["slot"], "b")
        self.assertEqual(p["boot_sha"], sha(NEW))
        self.assertEqual(p["kernel_version"], "5.10.269")
        self.assertEqual(p["modules"], {"susfs4ksu": "on"})
        self.assertEqual(self.state.pending, p)
        self.assertEqual(State.load(self.state.path).pending["image_path"], p["image_path"])
        self.assertEqual(self.backups, 1)

    def test_refuses_unverified_without_flag(self):
        with self.assertRaises(install.InstallError) as c:
            self.prep(verified=False)
        self.assertIn("unverified", str(c.exception).lower())
        self.assertIsNone(self.state.pending)
        self.assertEqual(self.backups, 0)
        self.prep(verified=False, accept_unverified=True)

    def test_refuses_unknown_without_flag_and_names_them(self):
        with self.assertRaises(install.InstallError) as c:
            self.prep(accept_unknown=False)
        self.assertIn("uapi", str(c.exception))
        self.assertIsNone(self.state.pending)
        self.assertEqual(self.backups, 0)

    def test_accepted_unknowns_stay_recorded(self):
        self.assertTrue(any("uapi" in u for u in self.prep()["accepted_unknowns"]))

    def test_preflight_comes_first(self):
        self.state.rehearsal_passed = False
        with self.assertRaises(install.InstallError) as c:
            self.prep()
        self.assertIn("rehearsal", str(c.exception))
        self.assertEqual(self.backups, 0)

    def test_rejected_zip_makes_no_backup(self):
        dev = InstDev(running_sha=hashlib.sha256(image()).hexdigest())
        with self.assertRaises(install.InstallError) as c:
            self.prep(dev=dev)
        self.assertIn("identical", str(c.exception))
        self.assertEqual(self.backups, 0)

    def test_target_is_other_slot_when_running_b(self):
        self.state.known_good = "b"
        dev = InstDev(current="b")
        dev.part = {"a": SRC, "b": RUN}  # the backup of a is SRC's twin; make the files match
        for sl, data in (("a", SRC), ("b", RUN)):
            with open(os.path.join(self.backup_dir, f"boot_{sl}.img"), "wb") as f:
                f.write(data)
        self.assertEqual(self.prep(dev=dev)["slot"], "a")

    def test_never_targets_known_good(self):
        self.state.known_good = "b"  # running a, known good b: the only other slot is the known good one
        with self.assertRaises(install.InstallError):
            self.prep()

    def test_refuses_without_known_good_or_junk_slot(self):
        for good in (None, "c", "A", "a\n"):
            self.state.known_good = good
            with self.assertRaises(install.InstallError):
                self.prep()
        self.state.known_good = "a"
        self.dev.current = "../b"
        with self.assertRaises(install.InstallError):
            self.prep()

    def test_zip_changed_after_check_stops(self):
        real = install.check_zip

        def swap(path, dev, state):
            r = real(path, dev, state)
            with zipfile.ZipFile(path, "w") as z:
                z.writestr("Image", image(version=b"5.10.270"))
            return r
        with mock.patch("pkt.install.check_zip", swap):
            with self.assertRaises(install.InstallError) as c:
                self.prep()
        self.assertIn("changed", str(c.exception))
        self.assertIsNone(self.state.pending)

    def test_backup_not_matching_partition_stops(self):
        self.dev.part["b"] = b"SOMETHING ELSE"
        with self.assertRaises(install.InstallError) as c:
            self.prep()
        self.assertIn("backup", str(c.exception))

    def test_oversize_result_refused(self):
        def big(*a):
            p = fake_build(*a)
            raise install.BootImgError("new boot image is too big")
        with mock.patch("pkt.install.build_boot", big):
            with self.assertRaises(install.InstallError):
                self.prep()
        self.assertIsNone(self.state.pending)


class Install(Base):
    def test_refuses_without_pending(self):
        with self.assertRaises(install.InstallError):
            self.inst()

    def test_install_refuses_without_confirmed_copy(self):
        self.ready()
        with self.assertRaises(install.InstallError):
            self.inst(confirmed=False)
        self.assertEqual(self.dev.events, [])

    def test_happy_path_activates_only_after_match(self):
        self.ready()
        self.inst()
        self.assertEqual(self.dev.events, [("unbootable", "b"), ("write", "b"), ("flush", "b"),
                                           ("readback", "b"), ("set_active", "b")])
        self.assertEqual(self.dev.part["b"], NEW)
        self.assertEqual(self.state.pending["stage"], "installed")
        self.assertEqual(State.load(self.state.path).pending["stage"], "installed")

    def test_activate_only_after_match(self):
        self.ready()
        self.inst()
        names = [e[0] for e in self.dev.events]
        self.assertLess(names.index("flush"), names.index("readback"))
        self.assertLess(names.index("readback"), names.index("set_active"))

    def test_readback_mismatch_skips_activate(self):
        self.ready()
        self.dev.corrupt = True
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertIn("NOT activated", str(c.exception))
        self.assertNotIn(("set_active", "b"), self.dev.events)
        self.assertNotEqual(self.state.pending["stage"], "installed")

    def test_short_write_skips_activate(self):
        self.ready()
        self.dev.short_write = True
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertNotIn(("set_active", "b"), self.dev.events)
        self.assertNotEqual(self.state.pending["stage"], "installed")

    def test_dd_failure_skips_activate(self):
        self.ready()
        self.dev.write_fails = True
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertIn("NOT activated", str(c.exception))
        self.assertEqual([e for e in self.dev.events if e[0] == "set_active"], [])
        self.assertNotEqual(self.state.pending["stage"], "installed")

    def test_activation_failure_is_honest_and_retryable(self):
        self.ready()
        self.dev.activate_fails = True
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertIn("written and verified", str(c.exception))
        self.assertIn("slot a is active now", str(c.exception))  # a fresh read, not an assumption
        self.assertEqual(self.state.pending["stage"], "written")
        self.dev.activate_fails = False
        self.dev.events.clear()
        self.inst()  # a rerun finishes the job without rewriting
        self.assertNotIn(("write", "b"), self.dev.events)
        self.assertIn(("set_active", "b"), self.dev.events)
        self.assertEqual(self.state.pending["stage"], "installed")

    def test_crash_after_write_leaves_recoverable_state(self):
        self.ready()
        self.dev.set_active = lambda s: (_ for _ in ()).throw(KeyboardInterrupt())
        with self.assertRaises(KeyboardInterrupt):
            self.inst()
        self.assertEqual(State.load(self.state.path).pending["stage"], "written")

    def test_stage_is_saved_before_writing(self):
        self.ready()
        seen = []
        real = self.dev.write_boot
        self.dev.write_boot = lambda s, p: (seen.append(self.stage()), real(s, p))[1]
        self.inst()
        self.assertEqual(seen, ["writing"])

    def test_never_targets_current_slot(self):
        self.ready(slot="a")  # pending claims the running slot
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.dev.events, [])

    def test_never_targets_known_good(self):
        self.ready()
        self.state.known_good = "b"
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.dev.events, [])

    def test_bad_slot_values_refused(self):
        for slot in ("c", "B", "b ", "../b", None):
            self.ready(slot=slot)
            with self.assertRaises(install.InstallError):
                self.inst()
        self.assertEqual(self.dev.events, [])

    def test_write_boot_validates_slot(self):
        for s in ("c", "ab", "a;reboot", ""):
            with self.assertRaises(ValueError):
                Device().write_boot(s, "/x")

    def test_image_changed_on_disk_refused(self):
        self.ready()
        with open(self.state.pending["image_path"], "ab") as f:
            f.write(b"tamper")
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.dev.events, [])

    def test_bad_kernel_refused(self):
        self.ready()
        self.state.bad_kernels.append(self.state.pending["image_sha"])
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.dev.events, [])

    def test_image_larger_than_partition_refused(self):
        self.ready()
        for size in (len(NEW) - 1, len(NEW) + 1):  # must be equal, not merely fit
            self.dev.size = size
            with self.assertRaises(install.InstallError):
                self.inst()
        self.assertEqual(self.dev.events, [])

    def test_preflight_rerun(self):
        self.ready()
        self.state.rehearsal_passed = False
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.dev.events, [])

    def test_target_partition_changed_since_prepare_refused(self):
        self.ready()
        self.dev.part["b"] = b"OTA-UPDATED"
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.dev.events, [])

    def test_runbook_failure_stops_before_write(self):
        self.ready()
        def boom(cur): raise OSError("disk")
        with self.assertRaises(install.InstallError):
            install.install(self.dev, self.state, True, runbook=boom)
        self.assertEqual(self.dev.events, [])

    def test_installed_not_reinstalled(self):
        self.ready()
        self.inst()
        self.dev.events.clear()
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.dev.events, [])


class Fixes(Base):
    # --- C1 ---
    def test_prepare_refuses_over_unresolved_stages_and_keeps_everything(self):
        self.ready()
        keep = dict(self.state.pending)
        for stage in ("writing", "write_failed", "written", "installed"):
            self.state.pending["stage"] = stage
            with self.assertRaises(install.InstallError) as c:
                self.prep()
            msg = str(c.exception)
            self.assertIn("boot_b.img" if stage != "installed" else "post-check", msg)
            self.assertEqual(self.backups, 1)  # no new backup, nothing rebuilt
            self.assertTrue(os.path.exists(keep["image_path"]))
            self.assertTrue(os.path.exists(keep["source_copy"]))

    def test_good_image_and_backup_survive_outside_work(self):
        p = self.prep()
        self.assertNotIn(os.sep + "work" + os.sep, p["image_path"])
        self.assertEqual(p["backup"], self.backup_dir)
        self.assertEqual(bootimg.sha(p["source_copy"]), p["source_sha"])

    def test_prepare_allowed_again_over_prepared(self):
        self.ready()
        self.prep()

    def test_discard_needs_slot_restored(self):
        self.ready(stage="write_failed")
        self.dev.part["b"] = b"HALF".ljust(len(NEW), b"\0")
        with self.assertRaises(install.InstallError):
            install.discard(self.dev, self.state)
        self.assertIsNotNone(self.state.pending)
        self.dev.part["b"] = SRC
        install.discard(self.dev, self.state)
        self.assertIsNone(State.load(self.state.path).pending)

    def test_discard_refuses_when_target_is_active(self):
        self.ready(stage="installed")
        self.dev.active = "b"
        with self.assertRaises(install.InstallError):
            install.discard(self.dev, self.state)

    # --- C2 ---
    def test_flush_failure_is_write_failed(self):
        self.ready()
        self.dev.flush_fails = True
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.stage(), "write_failed")
        self.assertNotIn(("set_active", "b"), self.dev.events)
        self.assertNotIn(("readback", "b"), self.dev.events)

    # --- C3 ---
    def test_refuses_when_other_slot_is_already_armed(self):
        self.ready()
        self.dev.active = "b"
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertIn("armed", str(c.exception))
        self.assertEqual(self.dev.events, [])

    def test_marks_target_unbootable_before_writing_and_failure_stops(self):
        self.ready()
        self.inst()
        self.assertEqual(self.dev.events[0], ("unbootable", "b"))
        self.setUp()
        self.ready()
        self.dev.unbootable_fails = True
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertNotIn(("write", "b"), self.dev.events)

    def test_failure_message_reads_active_slot_afresh(self):
        self.ready()
        self.dev.corrupt = True
        self.dev.active = "b"  # something armed it meanwhile; the message must say so, not assume
        orig = self.dev.active_slot
        calls = []
        self.dev.active_slot = lambda: calls.append(1) or ("a" if len(calls) == 1 else "b")
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertIn("slot b IS the active slot", str(c.exception))
        self.assertIn("bootctl set-active-boot-slot 0", str(c.exception))

    def test_rerun_from_write_failed_rewrites(self):
        self.ready()
        self.dev.corrupt = True
        with self.assertRaises(install.InstallError):
            self.inst()
        self.dev.corrupt = False
        self.dev.events.clear()
        self.inst()
        self.assertIn(("write", "b"), self.dev.events)
        self.assertEqual(self.stage(), "installed")

    def test_rerun_from_written_when_already_armed_only_verifies(self):
        self.ready()
        self.dev.activation_ignored = True
        self.dev.part["b"] = NEW
        self.state.pending["stage"] = "written"
        self.dev.active = "b"  # crashed right after set_active
        self.inst()
        self.assertEqual([e[0] for e in self.dev.events], ["readback"])
        self.assertEqual(self.stage(), "installed")

    def test_rerun_from_written_corrupt_slot_rewrites_next_time(self):
        self.ready()
        self.state.pending["stage"] = "written"
        self.dev.part["b"] = SRC  # not what was written
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.stage(), "write_failed")
        self.assertNotIn(("write", "b"), self.dev.events)  # this run only looked

    # --- I1 ---
    def test_requires_current_slot_successful(self):
        self.ready()
        self.dev.successful["a"] = False
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertIn("bootctl mark-boot-successful", str(c.exception))
        self.assertEqual(self.dev.events, [])

    def test_activation_must_be_confirmed(self):
        self.ready()
        self.dev.activation_ignored = True
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertIn("did not take", str(c.exception))
        self.assertEqual(self.stage(), "written")

    def test_unbootable_after_activation_is_not_installed(self):
        self.ready()
        orig = self.dev.set_active
        def act(s):
            orig(s)
            self.dev.bootable[s] = False
        self.dev.set_active = act
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.stage(), "written")

    def test_merge_status_reread_before_activation(self):
        self.ready()
        real = self.dev.boot_prefix_hash
        def later(slot, n):
            self.dev.merge = "merging"
            return real(slot, n)
        self.dev.boot_prefix_hash = later
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertNotIn(("set_active", "b"), self.dev.events)
        self.assertEqual(self.stage(), "written")

    # --- I5 ---
    def test_running_slot_backup_must_exist_and_match(self):
        self.ready()
        os.remove(os.path.join(self.backup_dir, "boot_a.img"))
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.dev.events, [])
        self.setUp()
        with open(os.path.join(self.backup_dir, "boot_a.img"), "wb") as f:
            f.write(b"stale")
        with self.assertRaises(install.InstallError):
            self.prep()

    def test_changed_message_does_not_recommend_prepare(self):
        self.ready()
        self.dev.part["b"] = b"OTA".ljust(len(NEW), b"\0")
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertNotIn("run pkt prepare", str(c.exception))

    # --- I9 ---
    def test_slot_sources_must_agree(self):
        def bad():
            raise ValueError("bootctl says a but bootconfig says _b")
        self.dev.verified_slot = bad
        with self.assertRaises(install.InstallError):
            self.prep()
        self.setUp()
        self.ready()
        self.dev.verified_slot = bad
        with self.assertRaises(install.InstallError):
            self.inst()
        self.assertEqual(self.dev.events, [])


class Round2(Base):
    def test_armed_rerun_with_bad_readback_says_it_is_active(self):
        self.ready()
        self.state.pending["stage"] = "written"
        self.dev.active = "b"
        self.dev.part["b"] = SRC
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        m = str(c.exception)
        self.assertNotIn("NOT activated", m)
        self.assertIn("IS the active slot", m)
        self.assertIn("bootctl set-active-boot-slot 0", m)
        self.assertEqual(self.stage(), "write_failed")

    def test_nothing_written_only_on_first_attempt(self):
        self.ready()
        self.dev.active = "b"
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertIn("Nothing written.", str(c.exception))
        for stage in ("writing", "write_failed"):
            self.state.pending["stage"] = stage
            self.dev.successful["a"] = False
            with self.assertRaises(install.InstallError) as c:
                self.inst()
            self.assertNotIn("Nothing written", str(c.exception))
            self.assertIn("partly written", str(c.exception))

    def test_prepare_over_prepared_refuses_if_slot_changed(self):
        self.ready()
        self.dev.part["b"] = b"MANUAL-FLASH".ljust(len(NEW), b"\0")
        with self.assertRaises(install.InstallError) as c:
            self.prep()
        self.assertIn(self.backup_dir, str(c.exception))
        self.assertEqual(self.backups, 1)
        self.assertEqual(self.state.pending["source_sha"], sha(SRC))

    def test_failures_after_marking_name_the_unbootable_slot(self):
        for how in ("corrupt", "flush_fails", "write_fails"):
            self.setUp()
            self.ready()
            setattr(self.dev, how, True)
            with self.assertRaises(install.InstallError) as c:
                self.inst()
            self.assertIn("marked unbootable", str(c.exception), how)
            self.assertIn("fastboot --set-active=b", str(c.exception))
        self.setUp()
        self.ready()
        self.dev.activate_fails = True
        with self.assertRaises(install.InstallError) as c:
            self.inst()
        self.assertIn("marked unbootable", str(c.exception))

    def test_prepare_refusal_over_crashed_install_mentions_unbootable(self):
        self.ready(stage="writing")
        with self.assertRaises(install.InstallError) as c:
            self.prep()
        self.assertIn("unbootable", str(c.exception))

    def test_discard_states_unbootable_and_does_not_clear_it(self):
        self.ready(stage="write_failed")
        self.dev.bootable["b"] = False
        note = install.discard(self.dev, self.state)
        self.assertIn("marked unbootable", note)
        self.assertIn("bootctl set-active-boot-slot 1", note)
        self.assertFalse(self.dev.bootable["b"])
        self.assertEqual([e for e in self.dev.events if e[0] == "set_active"], [])

    def test_discard_flushes_before_hashing(self):
        self.ready(stage="write_failed")
        order = []
        self.dev.flush_boot = lambda s: order.append("flush")
        real = self.dev.partition_hash
        self.dev.partition_hash = lambda n: (order.append("hash"), real(n))[1]
        install.discard(self.dev, self.state)
        self.assertEqual(order, ["flush", "hash"])

    def test_corrupt_state_prints_clean_error_and_refuses(self):
        err = io.StringIO()
        with mock.patch("pkt.cli.State.load", side_effect=ValueError("corrupt state file x")), \
                contextlib.redirect_stderr(err):
            rc = cli.main(["status"])
        self.assertEqual(rc, 1)
        self.assertIn("error: corrupt state file x", err.getvalue())

    def test_device_root_has_no_python_timeout_and_reports_124(self):
        calls = []

        def run(argv, **kw):
            calls.append(kw)
            return subprocess.CompletedProcess(argv, 124, "", "")
        with mock.patch("pkt.device.subprocess.run", run):
            with self.assertRaises(RootError) as c:
                Device().root("timeout 2 sleep 8")
        self.assertNotIn("timeout", calls[0])
        self.assertIn("timed out", str(c.exception))


class ModelledPhone:
    """Stands in for subprocess.run under a REAL Device: it models the flash, the page cache and bootctl."""

    def __init__(self, lost_write=False):
        self.disk = {"a": RUN, "b": SRC}
        self.cache = {}
        self.active, self.current = "a", "a"
        self.ok = {"a": True, "b": False}
        self.bootable = {"a": True, "b": True}
        self.lost_write = lost_write
        self.calls, self.kwargs, self.unexpected, self.violations = [], [], [], []

    def view(self, slot):
        return self.cache.get(slot, self.disk[slot])

    def __call__(self, argv, **kw):
        self.calls.append(argv)
        self.kwargs.append(kw)
        out, rc = self.answer(argv)
        return subprocess.CompletedProcess(argv, rc, out, "")

    def answer(self, argv):
        if len(argv) != 3 or argv[:2] != ["su", "-c"]:
            self.unexpected.append(argv)
            return "", 127
        cmd, dev = argv[2], "/dev/block/by-name/"
        bc = "/data/adb/ksu/bin/bootctl "
        n = {"0": "a", "1": "b"}
        if cmd == "grep CapEff /proc/self/status":
            return "CapEff:\t000001ffffffffff\n", 0
        if cmd == "cat /sys/class/power_supply/battery/capacity":
            return "80\n", 0
        if cmd == bc + "get-snapshot-merge-status":
            return "none\n", 0
        if cmd == "getprop ro.build.fingerprint":
            return "Nothing/Pong/fp:16\n", 0
        if cmd == "cat /proc/sys/kernel/random/boot_id":
            return "477e1468-e714-482c-839d-b7d4b8a35124\n", 0
        if cmd == "cat /proc/bootconfig":
            return f'androidboot.vbmeta.device_state = "unlocked"\nandroidboot.slot_suffix = "_{self.current}"\n', 0
        if cmd == bc + "get-current-slot":
            return {"a": "0", "b": "1"}[self.current] + "\n", 0
        if cmd == bc + "get-active-boot-slot":
            return {"a": "0", "b": "1"}[self.active] + "\n", 0
        if cmd.startswith(bc + "is-slot-marked-successful "):
            return "", 0 if self.ok[n[cmd[-1]]] else 1
        if cmd.startswith(bc + "is-slot-bootable "):
            return "", 0 if self.bootable[n[cmd[-1]]] else 1
        if cmd.startswith(bc + "set-slot-as-unbootable "):
            self.bootable[n[cmd[-1]]] = False
            return "", 0
        if cmd.startswith(bc + "set-active-boot-slot "):
            self.active = n[cmd[-1]]
            self.bootable[self.active] = True
            return "", 0
        m = re.fullmatch(r"sha256sum " + dev + r"(\w+)", cmd)
        if m:
            name = m[1]
            data = self.view(name[5:]) if name.startswith("boot_") else b"x"
            return hashlib.sha256(data).hexdigest() + "  x\n" if name.startswith("boot_") else "ab" * 32 + "  x\n", 0
        m = re.fullmatch(r"blockdev --getsize64 " + dev + r"boot_(\w)", cmd)
        if m:
            return f"{len(self.disk[m[1]])}\n", 0
        m = re.fullmatch(r"test -b " + dev + r"boot_(\w) && timeout -k 30 600 dd if=(\S+) of=" + dev + r"boot_(\w) bs=1M "
                         r"conv=notrunc,nocreat,fsync", cmd)
        if m:
            if m[1] != m[3]:
                self.unexpected.append(argv)
            if m[3] == self.current:
                self.violations.append("wrote the running slot")
            with open(m[2], "rb") as f:
                data = f.read()
            old = self.view(m[3])
            self.cache[m[3]] = data + old[len(data):]  # goes to the page cache first
            return "", 0
        m = re.fullmatch(r"timeout -k 30 600 sync && timeout -k 30 600 blockdev --flushbufs " + dev + r"boot_(\w)", cmd)
        if m:
            if not self.lost_write:
                self.disk[m[1]] = self.view(m[1])
            self.cache.pop(m[1], None)  # the cache is dropped either way
            return "", 0
        m = re.fullmatch(r"head -c (\d+) " + dev + r"boot_(\w) \| sha256sum", cmd)
        if m:
            return hashlib.sha256(self.view(m[2])[:int(m[1])]).hexdigest() + "  -\n", 0
        self.unexpected.append(argv)
        return "", 127


class RealDeviceArgv(Base):
    def test_exact_commands_in_order(self):
        phone = ModelledPhone()
        self.ready()
        self.dev = Device()
        with mock.patch("pkt.device.subprocess.run", phone):
            self.inst()
        cmds = [a[2] for a in phone.calls]
        img = self.state.pending["image_path"]
        bc = "/data/adb/ksu/bin/bootctl "
        dd = f"test -b /dev/block/by-name/boot_b && timeout -k 30 600 dd if={img} of=/dev/block/by-name/boot_b bs=1M conv=notrunc,nocreat,fsync"
        want = [bc + "set-slot-as-unbootable 1", dd, "timeout -k 30 600 sync && timeout -k 30 600 blockdev --flushbufs /dev/block/by-name/boot_b",
                f"head -c {len(NEW)} /dev/block/by-name/boot_b | sha256sum", bc + "set-active-boot-slot 1",
                bc + "get-active-boot-slot", bc + "is-slot-bootable 1"]
        it = iter(cmds)
        for w in want:  # the wanted commands occur, in this order
            self.assertTrue(any(c == w for c in it), w)
        self.assertEqual(phone.unexpected, [])
        self.assertEqual(phone.violations, [])
        self.assertTrue(all(isinstance(a, list) and a[:2] == ["su", "-c"] for a in phone.calls))
        # the timeout runs as root inside the command; a Python-side one cannot kill a uid 0 child
        self.assertTrue(all("timeout" not in k for k in phone.kwargs))
        self.assertEqual(phone.active, "b")
        self.assertEqual(phone.disk["b"], NEW)

    def test_page_cache_cannot_fake_a_good_write(self):
        phone = ModelledPhone(lost_write=True)  # the flash never got the data
        self.ready()
        self.dev = Device()
        with mock.patch("pkt.device.subprocess.run", phone):
            with self.assertRaises(install.InstallError):
                self.inst()
        cmds = [a[2] for a in phone.calls]
        self.assertFalse(any("set-active-boot-slot" in c for c in cmds))
        self.assertEqual(self.stage(), "write_failed")
        self.assertEqual(phone.active, "a")
        flush = next(i for i, c in enumerate(cmds) if "flushbufs" in c)
        self.assertLess(flush, next(i for i, c in enumerate(cmds) if c.startswith("head -c")))

    def test_hardcoded_boot_a_while_on_a_is_caught(self):
        phone = ModelledPhone()
        self.ready()
        self.dev = Device()
        with mock.patch("pkt.device.subprocess.run", phone), \
                mock.patch.object(Device, "_boot_dev", staticmethod(lambda slot: "/dev/block/by-name/boot_a")):
            with self.assertRaises(install.InstallError):
                self.inst()
        self.assertIn("wrote the running slot", phone.violations)  # the model sees it ...
        self.assertNotIn(("set-active-boot-slot 1"), " ".join(a[2] for a in phone.calls))  # ... and install notices

    def test_dd_timeout_rc_124_is_write_failed(self):
        phone = ModelledPhone()
        self.ready()
        self.dev = Device()

        def run(argv, **kw):
            if "dd if=" in argv[2]:
                return subprocess.CompletedProcess(argv, 124, "", "")  # what `timeout -k 30 600 dd` returns when it fires
            return phone(argv, **kw)
        with mock.patch("pkt.device.subprocess.run", run):
            with self.assertRaises(install.InstallError) as c:
                self.inst()
        self.assertIn("timed out", str(c.exception))
        self.assertEqual(self.stage(), "write_failed")
        self.assertEqual(phone.active, "a")
        self.assertIn("unbootable", str(c.exception))

    def test_slot_by_bootctl_and_bootconfig_must_agree(self):
        phone = ModelledPhone()
        phone.current = "a"
        orig = phone.answer
        phone.answer = lambda argv: ('androidboot.slot_suffix = "_b"\n', 0) if argv[2] == "cat /proc/bootconfig" else orig(argv)
        with mock.patch("pkt.device.subprocess.run", phone):
            with self.assertRaises(ValueError):
                Device().verified_slot()
            self.ready_dev = Device()
            with self.assertRaises(install.InstallError):
                install.target_slot(Device(), self.state)

    def test_path_with_spaces_is_quoted(self):
        phone = ModelledPhone()
        self.dev = Device()
        with mock.patch("pkt.device.subprocess.run", phone), contextlib.suppress(RootError):
            self.dev.write_boot("b", "/x y/$(reboot);z.img")  # the model rejects the odd path; only the argv matters
        self.assertIn("dd if='/x y/$(reboot);z.img' of=/dev/block/by-name/boot_b", phone.calls[0][2])


class Cli(Base):
    def run_cli(self, fn, *a, **kw):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = fn(*a, **kw)
        return rc, out.getvalue(), err.getvalue()

    def test_low_caps_prints_manual_steps(self):
        self.dev.caps = False  # low from the start: prepare works, install hands over
        self.prep(need_caps=False)
        rc, out, _ = self.run_cli(cli.install_cmd, self.dev, self.state, None)
        self.assertEqual(rc, 1)
        self.assertIn(self.state.pending["image_path"], out)
        self.assertIn("Kernel Flasher", out)
        self.assertIn("never to slot a", out)
        self.assertIn("/sdcard", out)
        self.assertIn("no su needed", out)
        self.assertIn("slot b", out)
        self.assertEqual([e for e in self.dev.events], [])

    def test_status_shows_pending_and_successful_flag(self):
        self.prep()
        rc, out, _ = self.run_cli(cli.status, self.dev, self.state)
        self.assertIn(f"pending: stage prepared, slot b, kernel 5.10.269, image {self.state.pending['image_sha'][:8]}", out)
        self.assertIn("running slot marked successful: True", out)
        self.dev.successful["a"] = False
        self.assertIn("running slot marked successful: False", self.run_cli(cli.status, self.dev, self.state)[1])

    def test_prepare_with_low_caps_needs_the_waiver(self):
        self.dev.caps = False
        with self.assertRaises(install.InstallError):
            self.prep()
        self.assertEqual(self.prep(need_caps=False)["stage"], "prepared")

    def test_low_caps_route_validates_first(self):
        self.dev.caps = False
        muts = (lambda: self.state.pending.update(stage="written"),
                lambda: self.state.pending.update(slot="a"),
                lambda: self.dev.part.update(b=b"CHANGED"),
                lambda: setattr(self.state, "known_good", "b"))
        for mut in muts:
            self.state.pending, self.state.known_good, self.dev.part["b"] = None, "a", SRC
            self.prep(need_caps=False)
            mut()
            rc, out, err = self.run_cli(cli.install_cmd, self.dev, self.state, None)
            self.assertEqual(rc, 1)
            self.assertNotIn("Kernel Flasher", out)
            self.assertTrue(err)

    def test_install_without_or_with_wrong_code_shows_expected(self):
        self.ready()
        for given in (None, "deadbeef"):
            rc, out, err = self.run_cli(cli.install_cmd, self.dev, self.state, given)
            self.assertEqual(rc, 1)
            self.assertIn(f"--confirmed-copy={TOKEN}", err)
        self.assertEqual(self.dev.events, [])

    def test_install_prints_ready_and_the_way_back(self):
        self.ready()
        with mock.patch("pkt.cli.write_runbook"):
            rc, out, _ = self.run_cli(cli.install_cmd, self.dev, self.state, TOKEN)
        self.assertEqual(rc, 0)
        self.assertIn("Ready: restart your phone now", out)
        self.assertIn("pkt post-check", out)
        self.assertIn("OrangeFox", out)
        self.assertIn("fastboot --set-active=a", out)

    def test_install_failure_exit_1(self):
        self.ready()
        self.dev.corrupt = True
        with mock.patch("pkt.cli.write_runbook"):
            rc, out, err = self.run_cli(cli.install_cmd, self.dev, self.state, TOKEN)
        self.assertEqual(rc, 1)
        self.assertNotIn("Ready", out)

    def test_prepare_cmd_refusal_lists_unknowns_and_exits_1(self):
        rc, out, err = self.run_cli(cli.prepare_cmd, self.dev, self.state, self.zip, ["--accept-unverified"],
                                  backup=self.backup)
        self.assertEqual(rc, 1)
        self.assertIn("--accept-unknown", err)
        self.assertIn("uapi", err)

    def test_prepare_cmd_ok(self):
        rc, out, err = self.run_cli(cli.prepare_cmd, self.dev, self.state, self.zip,
                                    ["--accept-unknown", "--accept-unverified"], backup=self.backup)
        self.assertEqual(rc, 0, err)
        self.assertIn(self.backup_dir, out)
        self.assertIn(sha(RUN), out)
        self.assertIn("pkt-rescue.md", out)
        self.assertIn(f"pkt install --confirmed-copy={TOKEN}", out)
        self.assertIn("pkt post-check", out)
        self.assertIn("uapi", out)  # accepted unknowns remain visible

    def test_local_path_is_unverified_unless_digest_matches_a_verified_candidate(self):
        rc, _, err = self.run_cli(cli.prepare_cmd, self.dev, self.state, self.zip, ["--accept-unknown"],
                                  backup=self.backup)
        self.assertEqual(rc, 1)
        self.assertIn("unverified", err)
        with open(self.zip, "rb") as f:
            digest = sha(f.read())
        os.makedirs(os.path.dirname(self.state.path), exist_ok=True)
        with open(cli.candidates_path(self.state), "w") as f:
            json.dump([dict(name="x", sha256=digest, verified=True)], f)
        rc, _, err = self.run_cli(cli.prepare_cmd, self.dev, self.state, self.zip, ["--accept-unknown"],
                                  backup=self.backup)
        self.assertEqual(rc, 0, err)

    def test_discard_cmd(self):
        self.ready()
        rc, out, _ = self.run_cli(cli.discard_cmd, self.dev, self.state)
        self.assertEqual(rc, 0)
        self.assertIsNone(self.state.pending)

    def test_prepare_cmd_bad_flag(self):
        rc, _, _ = self.run_cli(cli.prepare_cmd, self.dev, self.state, self.zip, ["--yolo"], backup=self.backup)
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
