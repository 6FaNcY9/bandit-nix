import os
import tempfile
import unittest

from pkt.runbook import write_runbook
from pkt.state import State


class RunbookTest(unittest.TestCase):
    def test_runbook_names_known_good_and_backup(self):
        st = State(known_good="a", last_backup="/sdcard/Download/root-backups/x")
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "r.md")
            txt = write_runbook(st, p, current="b")
            with open(p) as fh:
                self.assertEqual(fh.read(), txt)
        for s in ("root-backups/x", "fastboot flash boot_a boot_a.img",
                  "fastboot flash boot_b boot_b.img", "fastboot --set-active=a",
                  "fastboot boot orangefox-stock-kernel-boot.img", "Current slot: b"):
            self.assertIn(s, txt)
