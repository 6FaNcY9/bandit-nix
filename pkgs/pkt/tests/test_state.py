import os
import tempfile
import unittest

from pkt.state import State


class StateTest(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(tempfile.mkdtemp(), "sub", "state.json")

    def test_missing_gives_defaults(self):
        s = State.load(self.path)
        self.assertIsNone(s.baseline)
        self.assertIsNone(s.known_good)
        self.assertEqual(s.bad_kernels, [])

    def test_round_trip(self):
        s = State.load(self.path)
        s.known_good = "a"
        s.baseline = {"vendor_boot": "x"}
        s.bad_kernels = ["k1"]
        s.save()
        t = State.load(self.path)
        self.assertEqual((t.known_good, t.baseline, t.bad_kernels), ("a", {"vendor_boot": "x"}, ["k1"]))
        self.assertFalse(os.path.exists(self.path + ".tmp"))

    def test_corrupt_file_raises_not_resets(self):
        os.makedirs(os.path.dirname(self.path))
        with open(self.path, "w") as f:
            f.write("{not json")
        with self.assertRaises(ValueError):
            State.load(self.path)


if __name__ == "__main__":
    unittest.main()


class SaveSafetyTest(unittest.TestCase):
    def test_lock_excludes_a_second_holder(self):
        import tempfile, os
        from pkt.state import State
        with tempfile.TemporaryDirectory() as t:
            a, b = State(path=os.path.join(t, "s.json")), State(path=os.path.join(t, "s.json"))
            with a.lock():
                with self.assertRaises(RuntimeError):
                    with b.lock():
                        pass
            with b.lock():  # free again afterwards
                pass

    def test_save_leaves_no_temp_file_and_syncs_the_directory(self):
        import tempfile, os
        from unittest import mock
        from pkt.state import State
        with tempfile.TemporaryDirectory() as t:
            st = State(path=os.path.join(t, "s.json"), known_good="a")
            with mock.patch("pkt.state.os.fsync") as fs:
                st.save()
                st.save()
            self.assertEqual(fs.call_count, 4)  # file and directory, twice
            self.assertEqual(sorted(os.listdir(t)), ["s.json"])
            self.assertEqual(State.load(st.path).known_good, "a")
