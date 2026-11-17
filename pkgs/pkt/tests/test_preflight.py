import unittest

from pkt.preflight import preflight
from pkt.state import State
from tests.fakes import FakeDevice, GOOD_BASELINE, good_answers

BAT = "cat /sys/class/power_supply/battery/capacity"


def run(need_rehearsal=True, baseline=GOOD_BASELINE, rehearsal=True, **over):
    st = State(baseline=dict(baseline) if baseline else None)
    st.rehearsal_passed = rehearsal
    return preflight(FakeDevice(good_answers(**over)), st, need_rehearsal)


class PreflightTest(unittest.TestCase):
    def test_all_ok_returns_empty(self):
        self.assertEqual(run(), [])

    def test_refuses_low_battery(self):
        self.assertTrue(any("battery" in r for r in run(**{BAT: "29\n"})))
        self.assertEqual(run(**{BAT: "30\n"}), [])

    def test_refuses_merge_in_progress(self):
        r = run(**{"/data/adb/ksu/bin/bootctl get-snapshot-merge-status": "merging\n"})
        self.assertTrue(any("merg" in x for x in r))

    def test_refuses_missing_caps(self):
        r = run(**{"grep CapEff /proc/self/status": "CapEff:\t0000000000000000\n"})
        self.assertTrue(any("cap" in x.lower() for x in r))

    def test_refuses_without_rehearsal(self):
        self.assertTrue(any("rehearsal" in x for x in run(rehearsal=False)))
        self.assertEqual(run(need_rehearsal=False, rehearsal=False), [])

    def test_refuses_slot_mismatch(self):
        b = dict(GOOD_BASELINE, vendor_boot="cd" * 32)
        r = run(baseline=b)
        self.assertTrue(any("OTA" in x and "rehearsal" in x for x in r))

    def test_refuses_ab_hash_differ(self):
        r = run(**{"sha256sum /dev/block/by-name/vendor_boot_b": "cd" * 32 + "  x\n"})
        self.assertTrue(any("different builds" in x for x in r))

    def test_refuses_locked_or_unreadable_bootloader_state(self):
        r = run(**{"cat /proc/bootconfig": 'androidboot.vbmeta.device_state = "locked"\n'})
        self.assertTrue(any("unlocked" in x for x in r))
        self.assertTrue(run(**{"cat /proc/bootconfig": "nothing here\n"}))

    def test_vbmeta_and_dtbo_must_match_between_slots(self):
        for p in ("vbmeta", "dtbo"):
            r = run(**{f"sha256sum /dev/block/by-name/{p}_b": "cd" * 32 + "  x\n"})
            self.assertTrue(any(p in x and "different builds" in x for x in r), p)

    def test_need_caps_false_waives_only_caps(self):
        st = State(baseline=dict(GOOD_BASELINE), rehearsal_passed=True)
        d = FakeDevice(good_answers(**{"grep CapEff /proc/self/status": "CapEff:\t0000000000000000\n",
                                       BAT: "5\n"}))
        r = preflight(d, st, need_caps=False)
        self.assertEqual(len(r), 1)
        self.assertIn("battery", r[0])

    def test_no_baseline_skips_fingerprint(self):
        self.assertEqual(run(baseline=None, **{"getprop ro.build.fingerprint": "other"}), [])

    def test_fingerprint_mismatch(self):
        self.assertTrue(run(**{"getprop ro.build.fingerprint": "other"}))


if __name__ == "__main__":
    unittest.main()
