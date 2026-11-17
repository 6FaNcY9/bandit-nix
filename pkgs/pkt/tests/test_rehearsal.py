import unittest

from pkt.rehearsal import RehearsalError, rehearse_check, rehearse_finish, rehearse_start
from pkt.state import State
from tests.fakes import FakeDevice, GOOD_BASELINE, good_answers

CUR = "/data/adb/ksu/bin/bootctl get-current-slot"


def dev(slot="0", **over):
    d = FakeDevice(good_answers(**{CUR: slot + "\n"}, **over))
    d.set_active = lambda s: d.calls.append("set_active " + s)
    return d


class Backup:
    def __init__(self, fail=False):
        self.fail, self.n = fail, 0

    def __call__(self):
        self.n += 1
        if self.fail:
            raise RuntimeError("backup failed")
        return "/sdcard/Download/root-backups/x"


class RehearsalTest(unittest.TestCase):
    def test_start_refuses_from_slot_b(self):
        d, b = dev("1"), Backup()
        with self.assertRaises(RehearsalError):
            rehearse_start(d, State(), b)
        self.assertEqual(b.n, 0)

    def test_start_stops_if_backup_fails(self):
        d = dev()
        with self.assertRaises(RuntimeError):
            rehearse_start(d, State(), Backup(fail=True))
        self.assertNotIn("set_active b", d.calls)

    def test_start_refuses_on_preflight_before_backup(self):
        d, b = dev(**{"cat /sys/class/power_supply/battery/capacity": "5\n"}), Backup()
        with self.assertRaises(RehearsalError) as c:
            rehearse_start(d, State(), b)
        self.assertIn("battery", str(c.exception))
        self.assertEqual(b.n, 0)

    def test_start_ok(self):
        d, st = dev(), State()
        st.path = "/dev/null.tmp-unused"
        st.save = lambda: None
        rehearse_start(d, st, Backup())
        self.assertEqual(st.last_backup, "/sdcard/Download/root-backups/x")
        self.assertEqual(d.calls[-1], "set_active b")

    def test_start_refuses_over_unresolved_install(self):
        for stage in ("writing", "write_failed", "written", "installed"):
            d, b = dev(), Backup()
            with self.assertRaises(RehearsalError):
                rehearse_start(d, State(pending=dict(stage=stage, slot="b")), b)
            self.assertEqual(b.n, 0)

    def test_start_requires_boot_b_intact_when_prepared(self):
        import hashlib
        good = hashlib.sha256(b"x").hexdigest()
        pend = dict(stage="prepared", slot="b", source_sha=good)
        d = dev(**{"sha256sum /dev/block/by-name/boot_b": "ff" * 32 + "  x\n"})
        with self.assertRaises(RehearsalError):
            rehearse_start(d, State(pending=dict(pend)), Backup())
        d = dev(**{"sha256sum /dev/block/by-name/boot_b": good + "  x\n"})
        st = State(pending=dict(pend))
        st.save = lambda: None
        rehearse_start(d, st, Backup())
        self.assertEqual(d.calls[-1], "set_active b")

    def test_start_ignores_stale_baseline(self):
        d, st = dev(), State(baseline=dict(GOOD_BASELINE, fingerprint="old"), rehearsal_passed=True)
        st.save = lambda: None
        rehearse_start(d, st, Backup())
        self.assertEqual(d.calls[-1], "set_active b")

    def test_start_refuses_when_slots_differ(self):
        d, b = dev(**{"sha256sum /dev/block/by-name/vendor_boot_b": "cd  x\n"}), Backup()
        with self.assertRaises(RehearsalError) as c:
            rehearse_start(d, State(), b)
        self.assertIn("different builds", str(c.exception))
        self.assertEqual(b.n, 0)

    def test_restart_clears_old_boot_record(self):
        d, st = dev(), State(b_booted_at="old", rehearsal_passed=True)
        st.save = lambda: None
        rehearse_start(d, st, Backup())
        with self.assertRaises(RehearsalError):
            rehearse_finish(d, st)

    def test_runbook_failure_stops_before_switch(self):
        d = dev()

        def bad():
            raise OSError("disk full")
        with self.assertRaises(RehearsalError):
            rehearse_start(d, State(), Backup(), bad)
        self.assertNotIn("set_active b", d.calls)

    def test_check_refuses_on_slot_a(self):
        st = State()
        with self.assertRaises(RehearsalError):
            rehearse_check(st, lambda k: "_a")
        self.assertIsNone(st.b_booted_at)

    def test_check_on_b_records(self):
        st = State()
        st.save = lambda: None
        rehearse_check(st, lambda k: "_b")
        self.assertTrue(st.b_booted_at)

    def test_finish_requires_b_booted(self):
        with self.assertRaises(RehearsalError):
            rehearse_finish(dev(), State())

    def test_finish_requires_slot_a(self):
        with self.assertRaises(RehearsalError):
            rehearse_finish(dev("1"), State(b_booted_at="t"))

    def test_finish_records_baseline(self):
        st = State(b_booted_at="t")
        st.save = lambda: None
        rehearse_finish(dev(), st)
        self.assertEqual(st.baseline, GOOD_BASELINE)
        self.assertEqual(st.known_good, "a")
        self.assertTrue(st.rehearsal_passed)
