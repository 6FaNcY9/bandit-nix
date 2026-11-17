import contextlib
import io
import json
import os
import tempfile
import unittest
from unittest import mock

from pkt import cli, install, postcheck
from pkt.device import Device, RootError
from pkt.postcheck import PostCheckError, forgive, mark_bad, post_check, switch_back
from pkt.rehearsal import RehearsalError, rehearse_finish, rehearse_start
from pkt.runbook import write_runbook
from pkt.state import State
from tests import test_install as ti
from tests.fakes import FakeDevice
from tests.test_install import InstDev, NEW, RUN, SRC, sha

# Real strings from the phone (r22 kernel, live module.prop files, ps -A)
BANNER = ("Linux version 5.10.269-android12-Wild (build-user@build-host) (Android (7284624, based on r416183b) clang "
          "version 12.0.5 (https://android.googlesource.com/toolchain/llvm-project "
          "c935d99d7cf2016289302412d708641d52d2f7ee), LLD 12.0.5 (/buildbot/src/android/llvm-toolchain/out/"
          "llvm-project/lld c935d99d7cf2016289302412d708641d52d2f7ee)) #1 SMP PREEMPT Mon Oct 5 04:20:00 UTC 2026")
REZYGISK_OK = "[Monitor: ✅, ReZygisk 64-bit: ✅, ReZygisk 32-bit: ✅] Standalone implementation of Zygisk."
SUSFS_OK = "status: ✅ SuS ඞ"
PS = ("NAME\ninit\nzygisk-ptrace64\nzygote64\nzygote\nzygiskd64\nzygiskd32\nzygiskd64-treat_wheel\n")
OLD_ID, NEW_ID = "477e1468-e714-482c-839d-b7d4b8a35124", "9d2e4f10-0000-4000-8000-000000000002"
IMG_SHA = "ab" * 32


class PCDev(InstDev):
    """Running on the target slot b (the new kernel), freshly restarted, with every check passing."""

    def __init__(self, current="b", **kw):
        super().__init__(current=current, kernel=BANNER + "\n", **kw)
        self.part = {"a": RUN, "b": NEW}
        self.active = current
        self.successful = {"a": True, "b": False}
        self.root_ok = True
        self.mods = {"susfs4ksu": "on", "rezygisk": "on"}
        self.desc = {"rezygisk": REZYGISK_OK, "susfs4ksu": SUSFS_OK}
        self.up, self.done, self.bid = 120.0, True, NEW_ID
        self.procs = {"zygisk-ptrace64", "zygiskd64", "zygiskd32", "zygote64"}
        self.susfs_ok = True
        self.mark_fails = False

    def has_root(self): return self.root_ok
    def prop_slot(self): return self.current
    def modules(self): return dict(self.mods)
    def uptime(self): return self.up
    def boot_completed(self): return self.done
    def boot_id(self): return self.bid
    def process_names(self): return set(self.procs)
    def susfs_answers(self): return self.susfs_ok
    def module_description(self, name): return self.desc[name]

    def mark_boot_successful(self):
        self.events.append(("mark",))
        if self.mark_fails:
            raise RootError("bootctl failed")
        self.successful[self.current] = True


def pending(stage="installed", **over):
    p = dict(slot="b", from_slot="a", image_path="/x", boot_sha=sha(NEW), kernel_version="5.10.269",
             kernel_banner=BANNER, image_sha=IMG_SHA, source="z", modules={"susfs4ksu": "on", "rezygisk": "on"},
             source_sha=sha(SRC), backup="/bk", stage=stage, boot_id=OLD_ID)
    p.update(over)
    return p


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.img = os.path.join(self.tmp.name, "new-boot_b.img")
        with open(self.img, "wb") as f:
            f.write(NEW)
        self.state = State(path=os.path.join(self.tmp.name, "state", "state.json"), known_good="a",
                           pending=pending(image_path=self.img))
        self.dev = PCDev()
        self.rb = []

    def pend(self, stage="installed", **over):
        self.state.pending = pending(stage, image_path=self.img, **over)

    def run_check(self, dev=None):
        return post_check(dev or self.dev, self.state, runbook=self.rb.append)

    def saved(self):
        return State.load(self.state.path)

    def assert_untouched(self, *, bad=0):
        self.assertEqual(self.state.known_good, "a")
        self.assertEqual(len(self.state.bad_kernels), bad)
        self.assertIsNotNone(self.state.pending)
        self.assertIsNone(self.state.known_good_image)

    def old(self, active="a", bootable=True, bid=NEW_ID):
        d = PCDev(current="a")
        d.active, d.bid = active, bid
        d.bootable["b"] = bootable
        return d


class Good(Base):
    def test_good_moves_known_good(self):
        r = self.run_check()
        self.assertEqual(r.outcome, "good")
        self.assertEqual(self.state.known_good, "b")
        self.assertIsNone(self.state.pending)
        s = self.saved()
        self.assertEqual((s.known_good, s.pending, s.bad_kernels), ("b", None, []))
        self.assertEqual(self.rb, ["b"])
        text = " ".join(r.details)
        self.assertIn("Play Integrity", text)
        self.assertIn("overwrites", text)
        self.assertIn("NOT checked", text)
        self.assertIn("HMA", text)

    def test_good_keeps_the_verified_image_and_the_runbook_names_it(self):
        self.run_check()
        img = self.state.known_good_image
        self.assertEqual((img["slot"], img["sha"]), ("b", sha(NEW)))
        with open(img["path"], "rb") as f:
            self.assertEqual(f.read(), NEW)
        self.assertNotEqual(img["path"], self.img)
        self.assertEqual(self.saved().known_good_image, img)
        txt = write_runbook(self.state, os.path.join(self.tmp.name, "r.md"), "b")
        self.assertIn(img["path"], txt)
        self.assertIn(img["sha"], txt)

    def test_runbook_ignores_image_of_another_slot(self):
        st = State(known_good="a", known_good_image=dict(slot="b", path="/k/boot_b.img", sha="x"))
        self.assertNotIn("/k/boot_b.img", write_runbook(st, os.path.join(self.tmp.name, "r.md")))

    def test_unreadable_image_is_reported_not_fatal(self):
        self.state.pending["image_path"] = "/nonexistent"
        r = self.run_check()
        self.assertEqual(r.outcome, "good")
        self.assertIn("Could not keep", " ".join(r.details))
        self.assertIsNone(self.state.known_good_image)

    def test_marks_successful_only_when_not_already(self):
        self.run_check()
        self.assertEqual(self.dev.events, [("mark",)])
        self.dev.events.clear()
        self.pend()
        self.dev.successful["b"] = True
        self.run_check()
        self.assertEqual(self.dev.events, [])

    def test_mark_failure_names_the_repair_command(self):
        self.dev.mark_fails = True
        r = self.run_check()
        self.assertEqual(r.outcome, "good")
        self.assertIn("bootctl mark-boot-successful", " ".join(r.details))

    def test_runbook_failure_is_reported(self):
        def boom(cur): raise OSError("disk full")
        r = post_check(self.dev, self.state, runbook=boom)
        self.assertEqual(r.outcome, "good")
        self.assertIn("rescue runbook", " ".join(r.details))

    def test_next_target_alternates(self):
        self.run_check()
        self.assertEqual(install.target_slot(self.dev, self.state), ("b", "a"))

    def test_prepare_works_again_after_resolution(self):
        with self.assertRaises(install.InstallError) as c:
            install.prepare("z", self.dev, self.state, backup=lambda: "/bk")
        self.assertIn("post-check", str(c.exception))
        self.run_check()
        with self.assertRaises(install.InstallError) as c:
            install.prepare("/nonexistent.zip", self.dev, self.state, backup=lambda: "/bk")
        self.assertNotIn("not resolved", str(c.exception))  # got past the pending guard

    def test_run_twice_is_safe(self):
        self.run_check()
        self.assertEqual(self.run_check().outcome, "no_pending")
        self.assertEqual((self.state.known_good, self.state.bad_kernels), ("b", []))
        self.assertEqual(self.dev.events, [("mark",)])

    def test_written_stage_on_target_counts_as_installed(self):
        self.pend("written")
        self.assertEqual(self.run_check().outcome, "good")

    def test_manual_flash_with_stage_prepared(self):
        self.pend("prepared")
        self.assertEqual(self.run_check().outcome, "good")


class Identity(Base):
    def test_same_sublevel_different_build_fails(self):
        self.dev.v["kernel"] = BANNER.replace("Oct 5 04:20:00", "Oct 9 11:02:41") + "\n"
        r = self.run_check()
        self.assertEqual(r.outcome, "checks_failed")
        self.assertIn("banner differs", " ".join(r.details))
        self.assert_untouched()

    def test_older_sublevel_fails(self):
        self.dev.v["kernel"] = BANNER.replace("5.10.269", "5.10.237") + "\n"
        self.assertEqual(self.run_check().outcome, "checks_failed")

    def test_same_banner_other_image_is_caught_by_the_boot_hash(self):
        self.dev.part["b"] = b"A-REBUILD-WITH-THE-SAME-BANNER"
        r = self.run_check()
        self.assertEqual(r.outcome, "checks_failed")
        self.assertIn("boot_b does not match", " ".join(r.details))

    def test_missing_banner_in_the_record_fails(self):
        self.state.pending["kernel_banner"] = None
        r = self.run_check()
        self.assertEqual(r.outcome, "checks_failed")
        self.assertIn("no kernel banner", " ".join(r.details))

    def test_manual_flash_with_other_image_fails(self):
        self.pend("prepared")
        self.dev.part["b"] = b"SOMETHING-ELSE"
        r = self.run_check()
        self.assertEqual(r.outcome, "checks_failed")
        self.assertEqual(self.state.pending["stage"], "prepared")

    def test_manual_flash_without_restart_is_not_a_test(self):
        self.pend("prepared")
        self.dev.bid = OLD_ID
        r = self.run_check()
        self.assertEqual(r.outcome, "not_restarted")
        self.assert_untouched()
        self.assertEqual(self.dev.events, [])

    def test_missing_boot_id_is_unresolved(self):
        self.state.pending["boot_id"] = None
        self.assertEqual(self.run_check().outcome, "unresolved")
        self.assert_untouched()


class Hiding(Base):
    def failed(self, needle):
        r = self.run_check()
        self.assertEqual(r.outcome, "checks_failed")
        self.assertIn(needle, " ".join(r.details))
        self.assertIn("pkt switch-back", " ".join(r.details))
        self.assert_untouched()
        self.assertEqual(self.dev.events, [])  # never marked successful
        self.assertEqual(self.rb, [])
        return r

    def test_rezygisk_descriptions(self):
        bad = ["[Monitor: ⚠️, ReZygisk 64-bit: ✅, ReZygisk 32-bit: ✅] Standalone implementation of Zygisk.",
               "[Monitor: ⛔, ReZygisk 64-bit: ✅, ReZygisk 32-bit: ✅] Standalone implementation of Zygisk.",
               "[Monitor: ✅, ReZygisk 64-bit: ✅, ReZygisk 32-bit: ⛔] Standalone implementation of Zygisk.",
               "[Monitor: ✅, ReZygisk 64-bit: ❌, ReZygisk 32-bit: ✅] x", "failed 💢", "Zygote crashed",
               "Standalone implementation of Zygisk.", "ok", ""]
        for d in bad:
            with self.subTest(d=d):
                self.pend()
                self.dev.desc["rezygisk"] = d
                self.failed("rezygisk description")
        self.pend()
        self.dev.desc["rezygisk"] = REZYGISK_OK
        self.assertEqual(self.run_check().outcome, "good")

    def test_susfs_descriptions(self):
        for d in ("status: ⚠️ SuS", "status: ❌", "status: ⛔", "ok", "SuS ඞ", "failed 💢", ""):
            with self.subTest(d=d):
                self.pend()
                self.dev.desc["susfs4ksu"] = d
                self.failed("susfs4ksu description")

    def test_watched_modules_must_be_on(self):
        for st in ("OFF", "REMOVE"):
            self.pend()
            self.dev.mods["rezygisk"] = st
            self.failed("module rezygisk")
        self.pend()
        del self.dev.mods["susfs4ksu"]
        self.failed("susfs4ksu")

    def test_dead_zygisk_daemon_fails_even_with_a_healthy_description(self):
        for gone in ("zygiskd64", "zygisk-ptrace64", "zygiskd32"):
            self.pend()
            self.dev.procs.discard(gone)
            self.failed(f"process {gone} is not running")
            self.dev.procs.add(gone)

    def test_susfs_not_answering_fails(self):
        self.dev.susfs_ok = False
        self.failed("ksu_susfs show version")

    def test_module_change_fails_with_name(self):
        self.dev.mods["rezygisk"] = "OFF"
        self.failed("module rezygisk changed: on -> OFF")

    def test_new_and_missing_module_named(self):
        self.dev.mods = {"rezygisk": "on", "newmod": "on"}
        r = self.failed("module newmod is new")
        self.assertIn("module susfs4ksu is gone", " ".join(r.details))

    def test_all_failures_named_together(self):
        self.dev.mods["rezygisk"] = "OFF"
        self.dev.desc["susfs4ksu"] = "❌"
        text = " ".join(self.run_check().details)
        self.assertIn("rezygisk changed", text)
        self.assertIn("susfs4ksu description", text)

    def test_failed_then_rerun_is_same_and_records_nothing(self):
        self.dev.mods["rezygisk"] = "OFF"
        a, b = self.run_check(), self.run_check()
        self.assertEqual((a.outcome, a.details), (b.outcome, b.details))
        self.assert_untouched()

    def test_no_root_on_new_slot_gives_the_route_and_reads_nothing(self):
        self.dev.root_ok = False
        self.dev.root = lambda cmd, timeout=None: self.fail("read with root: " + cmd)
        r = self.run_check()
        self.assertEqual(r.outcome, "checks_failed")
        text = " ".join(r.details)
        self.assertIn("OrangeFox", text)
        self.assertIn("fastboot --set-active=a", text)
        self.assertIn("volume down", text)
        self.assert_untouched()

    def test_no_root_on_old_slot_does_not_say_pick_it(self):
        d = PCDev(current="a")
        d.root_ok = False
        text = " ".join(self.run_check(d).details)
        self.assertIn("already on slot a", text)
        self.assertNotIn("choose slot", text)


class Timing(Base):
    def test_too_early_records_nothing(self):
        for done, up in ((False, 300.0), (True, 30.0), (False, 5.0)):
            self.dev.done, self.dev.up = done, up
            r = self.run_check()
            self.assertEqual(r.outcome, "too_early")
            self.assert_untouched()
            self.assertEqual(self.dev.events, [])
            self.assertEqual(self.rb, [])

    def test_minimum_uptime_is_60(self):
        self.dev.up = 60.0
        self.assertEqual(self.run_check().outcome, "good")

    def test_unreadable_uptime_is_too_early(self):
        def boom(): raise RootError("no /proc")
        self.dev.uptime = boom
        self.assertEqual(self.run_check().outcome, "too_early")
        self.assert_untouched()

    def test_stale_text_after_too_early_then_checks_run_later(self):
        self.dev.up = 10
        self.run_check()
        self.dev.up = 200
        self.assertEqual(self.run_check().outcome, "good")


class ActiveSlot(Base):
    def test_good_needs_the_target_to_be_active(self):
        self.dev.active = "a"
        r = self.run_check()
        self.assertEqual(r.outcome, "checks_failed")
        self.assertIn("active", " ".join(r.details))
        self.assert_untouched()
        self.assertEqual(self.dev.events, [])

    def test_after_switch_back_the_next_post_check_does_not_bless_the_kernel(self):
        switch_back(self.dev, self.state)
        self.dev.active = "a"
        self.assertEqual(self.run_check().outcome, "checks_failed")
        self.assertEqual(self.state.known_good, "a")
        self.assertIsNotNone(self.state.pending)
        self.assertEqual(self.dev.events.count(("mark",)), 0)


class OldSlot(Base):
    def test_bootloader_gave_up_records_bad_with_reason(self):
        r = self.run_check(self.old("a", bootable=False))
        self.assertEqual(r.outcome, "fell_back")
        s = self.saved()
        self.assertEqual(s.bad_kernels, [IMG_SHA])
        self.assertIn("unbootable", s.bad_reasons[IMG_SHA])
        self.assertIsNone(s.pending)
        self.assertEqual(s.known_good, "a")

    def test_target_still_bootable_is_ambiguous_and_records_nothing(self):
        r = self.run_check(self.old("a", bootable=True))
        self.assertEqual(r.outcome, "unclear")
        self.assert_untouched()
        self.assertIn("pkt mark-bad", " ".join(r.details))

    def test_ambiguous_with_target_still_active_says_how_to_stop_the_retry(self):
        r = self.run_check(self.old("b"))
        self.assertEqual(r.outcome, "unclear")
        self.assertIn("bootctl set-active-boot-slot 0", " ".join(r.details))

    def test_mark_bad_resolves_an_ambiguous_one(self):
        self.run_check(self.old("a"))
        self.assertEqual(mark_bad(self.state)[0], IMG_SHA)
        self.assertEqual(self.state.bad_kernels, [IMG_SHA])
        self.assertEqual(self.state.bad_reasons[IMG_SHA], "marked bad by the user")
        self.assertIsNone(self.state.pending)

    def test_not_restarted_branches_on_active(self):
        r = self.run_check(self.old("b", bid=OLD_ID))
        self.assertEqual(r.outcome, "not_restarted")
        self.assertIn("restart to try it", " ".join(r.details))
        r = self.run_check(self.old("a", bid=OLD_ID))
        self.assertEqual(r.outcome, "not_restarted")
        self.assertIn("will NOT test", " ".join(r.details))
        self.assert_untouched()

    def test_fallback_twice_does_not_double_record(self):
        self.run_check(self.old("a", bootable=False))
        self.assertEqual(self.run_check(self.old("a", bootable=False)).outcome, "no_pending")
        self.assertEqual(self.state.bad_kernels, [IMG_SHA])

    def test_already_bad_not_added_twice(self):
        self.state.bad_kernels = [IMG_SHA]
        self.run_check(self.old("a", bootable=False))
        self.assertEqual(self.state.bad_kernels, [IMG_SHA])

    def test_written_on_old_slot_after_restart_warns_about_a_panic(self):
        self.pend("written")
        r = self.run_check(self.old("a"))
        self.assertEqual(r.outcome, "unresolved")
        self.assertIn("panicked", " ".join(r.details))
        self.assertIn("pkt mark-bad", " ".join(r.details))
        self.assert_untouched()

    def test_prepared_on_old_slot_is_not_a_fallback(self):
        self.pend("prepared")
        self.assertEqual(self.run_check(self.old("a")).outcome, "unresolved")
        self.assert_untouched()

    def test_writing_and_write_failed_name_the_route(self):
        for stage in ("writing", "write_failed"):
            self.pend(stage)
            r = self.run_check()
            self.assertEqual(r.outcome, "unresolved")
            text = " ".join(r.details)
            self.assertIn("pkt install", text)
            self.assertIn("pkt discard", text)
            self.assertEqual(self.dev.events, [])
            self.assert_untouched()

    def test_no_pending_reads_nothing(self):
        self.state.pending = None
        self.dev.root = lambda *a, **k: self.fail("device read")
        self.assertEqual(self.run_check().outcome, "no_pending")


class BadList(Base):
    def test_old_state_files_without_reasons_still_load(self):
        os.makedirs(os.path.dirname(self.state.path))
        with open(self.state.path, "w") as f:
            json.dump({"bad_kernels": ["ab" * 32], "known_good": "a"}, f)
        s = self.saved()
        self.assertEqual((s.bad_kernels, s.bad_reasons), (["ab" * 32], {}))

    def test_forgive_by_prefix(self):
        self.state.bad_kernels = ["abc123" + "0" * 58, "def456" + "0" * 58]
        self.state.bad_reasons = {self.state.bad_kernels[0]: "x"}
        self.assertEqual(forgive(self.state, "abc1"[:3] + "123"), "abc123" + "0" * 58)
        self.assertEqual(self.state.bad_kernels, ["def456" + "0" * 58])
        self.assertEqual(self.state.bad_reasons, {})
        self.assertEqual(self.saved().bad_kernels, ["def456" + "0" * 58])

    def test_forgive_refuses_ambiguous_missing_and_short(self):
        self.state.bad_kernels = ["abc123" + "0" * 58, "abc123" + "1" * 58]
        for pre in ("abc123", "ffffff", "abc", "", "zzzzzz"):
            with self.assertRaises(PostCheckError):
                forgive(self.state, pre)
        self.assertEqual(len(self.state.bad_kernels), 2)
        self.assertEqual(forgive(self.state, "abc1230"), "abc123" + "0" * 58)

    def test_mark_bad_with_a_sha_and_without_pending(self):
        self.state.pending = None
        with self.assertRaises(PostCheckError):
            mark_bad(self.state)
        with self.assertRaises(PostCheckError):
            mark_bad(self.state, "abc")
        mark_bad(self.state, "cd" * 32)
        self.assertEqual(self.state.bad_kernels, ["cd" * 32])


class SwitchBack(Base):
    def test_refuses_without_known_good(self):
        self.state.known_good = None
        with self.assertRaises(PostCheckError):
            switch_back(self.dev, self.state)
        self.assertEqual(self.dev.events, [])

    def test_refuses_when_known_good_is_current(self):
        self.state.known_good = "b"
        with self.assertRaises(PostCheckError) as c:
            switch_back(self.dev, self.state)
        self.assertIn("running", str(c.exception))
        self.assertEqual(self.dev.events, [])

    def test_refusal_mentions_still_active_other_slot(self):
        d = PCDev(current="a")
        d.active = "b"
        with self.assertRaises(PostCheckError) as c:
            switch_back(d, self.state)
        self.assertIn("set-active-boot-slot 0", str(c.exception))
        self.assertEqual(d.events, [])

    def test_switches_verifies_reports_both_slots_and_flags_pending(self):
        self.dev.bootable["a"] = False  # set-active clears it in the fake
        good, notes = switch_back(self.dev, self.state)
        self.assertEqual(good, "a")
        self.assertEqual(self.dev.events, [("set_active", "a")])
        self.assertEqual(self.dev.active, "a")
        self.assertEqual(len(notes), 2)
        self.assertIn("Slot a: bootable True", notes[1])
        self.assertEqual(self.state.pending["stage"], "installed")
        self.assertTrue(self.saved().pending["switched_back"])

    def test_activation_not_taking_effect_gives_fastboot_route(self):
        self.dev.activation_ignored = True
        with self.assertRaises(PostCheckError) as c:
            switch_back(self.dev, self.state)
        self.assertIn("fastboot --set-active=a", str(c.exception))
        self.assertNotIn("switched_back", self.state.pending)

    def test_still_unbootable_gives_fastboot_route(self):
        self.dev.bootable["a"] = False
        self.dev.set_active = lambda s: setattr(self.dev, "active", s)  # does not clear the mark
        with self.assertRaises(PostCheckError) as c:
            switch_back(self.dev, self.state)
        self.assertIn("unbootable", str(c.exception))
        self.assertIn("fastboot", str(c.exception))

    def test_bootctl_failure_gives_fastboot_route(self):
        self.dev.activate_fails = True
        with self.assertRaises(PostCheckError) as c:
            switch_back(self.dev, self.state)
        self.assertIn("fastboot --set-active=a", str(c.exception))

    def test_no_root_gives_both_routes(self):
        class NoRoot(Device):
            def root(self, cmd, timeout=None): raise RootError("su: permission denied")
        with self.assertRaises(PostCheckError) as c:
            switch_back(NoRoot(), self.state)
        text = str(c.exception)
        self.assertIn("fastboot --set-active=a", text)
        self.assertIn("OrangeFox", text)

    def test_after_a_switch_back_the_restart_does_not_condemn_the_kernel(self):
        switch_back(self.dev, self.state)
        r = self.run_check(self.old("a", bootable=True))
        self.assertEqual(r.outcome, "switched_back")
        self.assertIn(f"pkt mark-bad {IMG_SHA}", " ".join(r.details))
        self.assertEqual(self.state.bad_kernels, [])
        self.assertIsNone(self.state.pending)
        self.assertEqual(self.state.known_good, "a")


class MarkBad(Base):
    def test_pending_sha_given_explicitly_behaves_like_no_argument(self):
        sha_, _ = mark_bad(self.state, IMG_SHA)
        self.assertEqual(sha_, IMG_SHA)
        self.assertIsNone(self.state.pending)
        self.assertEqual(self.state.bad_reasons[IMG_SHA], "marked bad by the user")

    def test_good_refused_for_a_kernel_recorded_bad(self):
        # simulated sequence: restart into the target, user marks it bad by sha while pending, then post-check
        self.state.bad_kernels.append(IMG_SHA)
        r = self.run_check()
        self.assertEqual(r.outcome, "checks_failed")
        self.assertIn("recorded as bad", " ".join(r.details))
        self.assertIn(f"pkt forgive {IMG_SHA[:8]}", " ".join(r.details))
        self.assert_untouched(bad=1)
        self.assertEqual(self.dev.events, [])

    def test_mark_bad_refuses_half_written_stages(self):
        for stage in ("writing", "write_failed"):
            self.pend(stage)
            for arg in (None, IMG_SHA):
                with self.assertRaises(PostCheckError) as c:
                    mark_bad(self.state, arg)
                self.assertIn("pkt discard", str(c.exception))
                self.assertIn("pkt install", str(c.exception))
            self.assertEqual(self.state.bad_kernels, [])
            self.assertEqual(self.state.pending["stage"], stage)

    def test_warns_when_the_target_is_still_active(self):
        d = self.old("b")
        _, notes = mark_bad(self.state, None, d)
        self.assertIn("bootctl set-active-boot-slot 0", " ".join(notes))
        self.pend()
        _, notes = mark_bad(self.state, None, self.old("a"))
        self.assertEqual(notes, [])

    def test_cli_prints_the_warning(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            cli.dispatch(self.old("b"), self.state, ["mark-bad"], ["mark-bad"])
        self.assertIn("set-active-boot-slot 0", out.getvalue())


class Round2(Base):
    def test_read_error_on_old_slot_records_nothing(self):
        for broken in ("is_bootable", "active_slot"):
            d = self.old("a", bootable=False)  # would be "fell back" if the read were taken as an answer
            def boom(*a): raise RootError("su: transient")
            setattr(d, broken, boom)
            r = self.run_check(d)
            self.assertEqual(r.outcome, "unclear", broken)
            self.assertIn("could not be read", " ".join(r.details))
            self.assert_untouched()

    def test_unclear_gives_both_ways_out(self):
        text = " ".join(self.run_check(self.old("a")).details)
        self.assertIn("set-active-boot-slot 1", text)  # make the target active to test it
        self.assertIn(f"pkt forgive {IMG_SHA[:8]}", text)

    def test_missing_boot_id_names_an_exit(self):
        self.state.pending["boot_id"] = None
        self.assertIn("pkt mark-bad", " ".join(self.run_check().details))

    def test_prepare_refusal_names_exits_from_the_old_slot(self):
        with self.assertRaises(install.InstallError) as c:
            install.prepare("z", self.old("a"), self.state, backup=lambda: "/bk")
        self.assertIn("pkt mark-bad", str(c.exception))

    def test_stale_switched_back_does_not_hide_a_real_fallback(self):
        self.state.pending["switched_back"] = True
        r = self.run_check(self.old("a", bootable=False))
        self.assertEqual(r.outcome, "fell_back")
        self.assertEqual(self.state.bad_kernels, [IMG_SHA])

    def test_flag_cleared_when_the_target_is_active_again(self):
        self.state.pending["switched_back"] = True
        self.dev.mods["rezygisk"] = "OFF"
        r = self.run_check()
        self.assertEqual(r.outcome, "checks_failed")
        self.assertNotIn("switched_back", self.saved().pending)

    def test_manual_route_after_switch_back_gets_correct_advice(self):
        self.pend("prepared", switched_back=True)
        r = self.run_check(self.old("a"))
        self.assertEqual(r.outcome, "unresolved")
        text = " ".join(r.details)
        self.assertNotIn("Run `pkt install", text)
        self.assertIn("pkt discard", text)
        self.assertIn("pkt mark-bad", text)

    def test_second_good_replaces_the_first_kept_image(self):
        self.run_check()
        first = self.state.known_good_image["path"]
        img_a = os.path.join(self.tmp.name, "new-boot_a.img")
        with open(img_a, "wb") as f:
            f.write(RUN)
        self.state.pending = pending(slot="a", from_slot="b", boot_sha=sha(RUN), image_path=img_a, boot_id=NEW_ID,
                                     image_sha="cd" * 32)
        d = PCDev(current="a")
        d.part, d.active, d.bid = {"a": RUN, "b": NEW}, "a", "boot-3"
        d.successful = {"a": False, "b": True}
        d.v["kernel"] = BANNER + "\n"
        self.assertEqual(self.run_check(d).outcome, "good")
        img = self.state.known_good_image
        self.assertEqual((img["slot"], img["sha"]), ("a", sha(RUN)))
        with open(img["path"], "rb") as f:
            self.assertEqual(f.read(), RUN)
        self.assertFalse(os.path.exists(first))

    def test_old_slot_state_is_read_not_assumed(self):
        text = " ".join(self.run_check().details)
        self.assertIn("last known working, not re-tested", text)
        self.assertNotIn("still works", text)
        self.pend()
        self.dev.bootable["a"] = False
        self.assertIn("UNBOOTABLE", " ".join(self.run_check().details))

    def test_runbook_skips_a_kept_image_the_slot_no_longer_holds(self):
        st = State(known_good="b", known_good_image=dict(slot="b", path="/k/boot_b.img", sha="aa"))
        path = os.path.join(self.tmp.name, "r.md")
        self.assertIn("/k/boot_b.img", write_runbook(st, path, "a", lambda n: "aa"))
        self.assertNotIn("/k/boot_b.img", write_runbook(st, path, "a", lambda n: "bb"))
        def boom(n): raise RootError("x")
        self.assertIn("/k/boot_b.img", write_runbook(st, path, "a", boom))

    def test_rehearse_finish_drops_a_stale_kept_image(self):
        d = PCDev(current="a")
        d.part = {"a": RUN, "b": NEW}
        d.fingerprint = lambda: "fp"
        self.state.b_booted_at = "now"
        self.state.known_good_image = dict(slot="b", path="/k", sha="stale")
        rehearse_finish(d, self.state)
        self.assertIsNone(self.state.known_good_image)
        self.state.known_good_image = dict(slot="b", path="/k", sha=sha(NEW))
        rehearse_finish(d, self.state)
        self.assertIsNotNone(self.state.known_good_image)


class Rounds(Base):
    def test_good_b_then_install_a_then_fallback_then_next_target(self):
        self.assertEqual(self.run_check().outcome, "good")
        # round 2: install on a, running b
        self.state.pending = pending(slot="a", from_slot="b", image_sha="cd" * 32, boot_id=NEW_ID, image_path=self.img)
        running_b = PCDev(current="b")
        running_b.active = "a"
        running_b.bootable["a"] = False
        running_b.bid = "boot-3"
        r = self.run_check(running_b)
        self.assertEqual(r.outcome, "fell_back")
        self.assertEqual(self.state.bad_kernels, ["cd" * 32])
        self.assertEqual(self.state.known_good, "b")
        self.assertEqual(install.target_slot(running_b, self.state), ("b", "a"))
        self.assertIn("unbootable", self.state.bad_reasons["cd" * 32])

    def test_good_then_good_on_the_other_slot(self):
        self.run_check()
        self.state.pending = pending(slot="a", from_slot="b", boot_id=NEW_ID, boot_sha=sha(RUN), image_path=self.img)
        d = PCDev(current="a")
        d.part = {"a": RUN, "b": NEW}
        d.bid = "boot-3"
        d.active = "a"
        d.successful = {"a": False, "b": True}
        # the kept image (RUN bytes at self.img? no: NEW) does not match boot_sha: honest warning, still good
        r = self.run_check(d)
        self.assertEqual((r.outcome, self.state.known_good), ("good", "a"))


class Cli(Base):
    def call(self, argv, dev=None):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                mock.patch("pkt.cli.write_runbook", lambda *a, **k: None):
            rc = cli.dispatch(dev or self.dev, self.state, argv[:1], argv)
        return rc, out.getvalue(), err.getvalue()

    def test_post_check_good_exit_0(self):
        rc, out, _ = self.call(["post-check"])
        self.assertEqual(rc, 0)
        self.assertIn("good", out)

    def test_post_check_failure_exit_1_and_names_check(self):
        self.dev.mods["rezygisk"] = "OFF"
        rc, out, _ = self.call(["post-check"])
        self.assertEqual(rc, 1)
        self.assertIn("rezygisk", out)

    def test_post_check_no_pending_exit_0(self):
        self.state.pending = None
        rc, out, _ = self.call(["post-check"])
        self.assertEqual((rc, "no_pending" in out), (0, True))

    def test_switch_back_prints_restart_and_slot_states(self):
        rc, out, _ = self.call(["switch-back"])
        self.assertEqual(rc, 0)
        self.assertIn("restart", out.lower())
        self.assertIn("bootable", out)

    def test_switch_back_error_exit_1(self):
        self.state.known_good = None
        rc, _, err = self.call(["switch-back"])
        self.assertEqual(rc, 1)
        self.assertIn("known good", err)

    def test_mark_bad_and_forgive(self):
        rc, out, _ = self.call(["mark-bad"])
        self.assertEqual(rc, 0)
        self.assertIn(IMG_SHA, out)
        rc, out, _ = self.call(["forgive", IMG_SHA[:8]])
        self.assertEqual(rc, 0)
        self.assertEqual(self.state.bad_kernels, [])
        rc, _, err = self.call(["forgive", "ffffff"])
        self.assertEqual(rc, 1)

    def test_commands_take_the_state_lock(self):
        with mock.patch("pkt.cli.State") as S, mock.patch("pkt.cli.Device"), \
                mock.patch("pkt.cli.dispatch", return_value=0):
            for c in ("post-check", "switch-back", "mark-bad", "forgive"):
                S.reset_mock()
                cli.main([c])
                S.return_value.lock.assert_called_once()


class Rehearsal(Base):
    def a_dev(self):
        d = PCDev(current="a")
        d.part = {"a": RUN, "b": NEW}
        return d

    def test_start_refuses_over_installed_then_allows_after_resolution(self):
        self.state.known_good = "a"
        with self.assertRaises(RehearsalError):
            rehearse_start(self.a_dev(), self.state, lambda: "/bk")
        self.state.pending = None
        self.state.baseline = None
        rehearse_start(self.a_dev(), self.state, lambda: "/bk")

    def test_start_refuses_when_known_good_is_b(self):
        self.state.known_good, self.state.pending = "b", None
        with self.assertRaises(RehearsalError) as c:
            rehearse_start(self.a_dev(), self.state, lambda: "/bk")
        self.assertIn("known good slot is b", str(c.exception))
        self.assertEqual(self.a_dev().events, [])

    def test_finish_keeps_known_good_b_and_sets_a_from_none(self):
        d = self.a_dev()
        d.fingerprint = lambda: "fp"
        self.state.b_booted_at = "now"
        self.state.known_good = "b"
        rehearse_finish(d, self.state)
        self.assertEqual(self.state.known_good, "b")
        self.state.known_good = None
        rehearse_finish(d, self.state)
        self.assertEqual(self.state.known_good, "a")


class BootId(ti.Base):
    def setUp(self):
        super().setUp()

        class D(InstDev):
            def boot_id(s): return OLD_ID
        self.dev = D()

    def test_prepare_records_the_banner_and_boot_id_and_install_the_boot_id(self):
        p = self.prep()
        self.assertEqual(p["kernel_banner"], "Linux version 5.10.269-android12-Wild (x) #1 SMP")
        self.assertEqual(p["boot_id"], OLD_ID)
        self.dev.boot_id = lambda: "after-prepare"
        self.inst()
        self.assertEqual(self.state.pending["boot_id"], "after-prepare")
        self.assertNotIn("installed_at", self.state.pending)

    def test_install_keeps_the_prepare_id_when_its_own_read_fails(self):
        self.prep()
        def boom(): raise RootError("no su")
        self.dev.boot_id = boom
        self.inst()
        self.assertEqual(self.state.pending["boot_id"], OLD_ID)

    def test_unreadable_boot_id_is_none_not_a_crash(self):
        self.assertIsNone(self.prep(dev=InstDev())["boot_id"])  # InstDev.root always raises


class DeviceMethods(unittest.TestCase):
    def test_uptime_boot_id_boot_completed(self):
        d = FakeDevice({"cat /proc/uptime": "47746.70 234802.68\n",
                        "cat /proc/sys/kernel/random/boot_id": OLD_ID + "\n",
                        "getprop sys.boot_completed": "1\n"})
        self.assertEqual(d.uptime(), 47746.70)
        self.assertEqual(d.boot_id(), OLD_ID)
        self.assertTrue(d.boot_completed())
        self.assertFalse(FakeDevice({"getprop sys.boot_completed": "\n"}).boot_completed())

    def test_empty_output_is_a_clean_root_error(self):
        for cmd, f in (("cat /proc/uptime", "uptime"), ("cat /proc/sys/kernel/random/boot_id", "boot_id"),
                       ("sha256sum /dev/block/by-name/boot_a", None)):
            d = FakeDevice({cmd: "\n"})
            with self.assertRaises(RootError):
                d.partition_hash("boot_a") if f is None else getattr(d, f)()
        d = FakeDevice({"head -c 5 /dev/block/by-name/boot_a | sha256sum": ""})
        with self.assertRaises(RootError):
            d.boot_prefix_hash("a", 5)

    def test_process_names(self):
        d = FakeDevice({"ps -A -o NAME": PS})
        self.assertIn("zygiskd64", d.process_names())
        self.assertNotIn("NAME", d.process_names())
        with self.assertRaises(RootError):
            FakeDevice({"ps -A -o NAME": "NAME\n"}).process_names()

    def test_susfs_answers(self):
        cmd = "/data/adb/ksu/bin/ksu_susfs show version"
        self.assertTrue(FakeDevice({cmd: "v2.3.0\n"}).susfs_answers())
        self.assertFalse(FakeDevice({cmd: "\n"}).susfs_answers())
        self.assertFalse(FakeDevice({cmd: "error: not supported\n"}).susfs_answers())

    def test_module_description_real_format(self):
        d = FakeDevice({"cat /data/adb/modules/rezygisk/module.prop":
                        "id=rezygisk\nversion=v1\ndescription=" + REZYGISK_OK + "\n"})
        self.assertEqual(d.module_description("rezygisk"), REZYGISK_OK)
        with self.assertRaises(ValueError):
            FakeDevice({"cat /data/adb/modules/x/module.prop": "id=x\n"}).module_description("x")

    def test_has_root_and_mark(self):
        self.assertTrue(FakeDevice({"id -u": "0\n"}).has_root())
        self.assertFalse(FakeDevice({"id -u": "2000\n"}).has_root())
        self.assertFalse(FakeDevice({}).has_root())
        d = FakeDevice({"/data/adb/ksu/bin/bootctl mark-boot-successful": ""})
        d.mark_boot_successful()
        self.assertEqual(d.calls, ["/data/adb/ksu/bin/bootctl mark-boot-successful"])

    def test_prop_slot(self):
        with mock.patch("subprocess.run") as r:
            r.return_value.stdout = "_b\n"
            self.assertEqual(Device().prop_slot(), "b")
            r.return_value.stdout = "\n"
            self.assertIsNone(Device().prop_slot())


if __name__ == "__main__":
    unittest.main()
