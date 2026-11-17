import os
import unittest

from pkt import zipcheck
from tests.test_zipcheck import Dev
from pkt.state import State

DL = "/storage/emulated/0/Download"
BAKASU = os.path.join(DL, "5.10.269-android12-2026-10-BakaSU-AnyKernel3.zip")
RESUKISU = os.path.join(DL, "5.10.269-android12-lts-ReSukiSU-AnyKernel3.zip")


@unittest.skipUnless(os.path.exists(BAKASU), "r22 BakaSU zip absent")
class BakaSuZip(unittest.TestCase):
    def test_r22_bakasu_zip_identical_to_running_hash(self):
        r = zipcheck.check_zip(BAKASU, Dev(), State())
        self.assertTrue(r.image_sha.startswith("29a6ec00fcfe41fb"))
        self.assertEqual(r.rejects, [])
        self.assertEqual(r.info["susfs"], "v2.3.0")
        self.assertEqual(r.info["ksu_commit"], "d5e9e025")  # differs from ksud 516d3e87: shown as unknown
        self.assertTrue(r.needs_confirmation)
        dev = Dev(running_sha=r.image_sha)
        self.assertTrue(any("running" in x for x in zipcheck.check_zip(BAKASU, dev, State()).rejects))


@unittest.skipUnless(os.path.exists(RESUKISU), "ReSukiSU zip absent")
class ReSukiSuZip(unittest.TestCase):
    def test_resukisu_zip_rejected(self):
        r = zipcheck.check_zip(RESUKISU, Dev(), State())
        self.assertFalse(r.ok)
        self.assertTrue(any("BakaSU" in x for x in r.rejects))
