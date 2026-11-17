import unittest

from pkt.device import RootError
from pkt.device import Device
from tests.fakes import FakeDevice


class QueriesTest(unittest.TestCase):
    def test_ksud_uapi(self):
        d = FakeDevice({"/data/adb/ksud --version": "ksud 4.2.0-rc3-86-g516d3e87 (uapi: 6)\n"})
        self.assertEqual(d.ksud_uapi(), 6)

    def test_susfs_version(self):
        d = FakeDevice({"cat /data/adb/modules/susfs4ksu/module.prop":
                        "id=susfs4ksu\nversion=v2.3.0-R28\nversionCode=105002028\n"})
        self.assertEqual(d.susfs_version(), "v2.3.0-R28")

    def test_unparsable_is_error_the_caller_treats_as_unknown(self):
        d = FakeDevice({"/data/adb/ksud --version": "ksud 4.2\n"})
        with self.assertRaises(ValueError):
            d.ksud_uapi()


class BootctlAnswerTest(unittest.TestCase):
    def dev(self, rc):
        class D(Device):
            def root(self, cmd):
                if rc == 0:
                    return ""
                raise RootError("failed", rc)
        return D()

    def test_rc0_true_rc70_false(self):
        self.assertTrue(self.dev(0).is_bootable("b"))
        self.assertTrue(self.dev(0).is_successful("b"))
        self.assertFalse(self.dev(70).is_bootable("b"))
        self.assertFalse(self.dev(70).is_successful("b"))

    def test_other_failures_raise(self):
        for rc in (1, 124, 127, None):
            with self.assertRaises(RootError, msg=rc):
                self.dev(rc).is_bootable("b")
            with self.assertRaises(RootError, msg=rc):
                self.dev(rc).is_successful("b")

    def test_real_root_carries_returncode(self):
        import subprocess
        from unittest import mock
        for rc in (70, 124, 3):
            with mock.patch("pkt.device.subprocess.run", lambda argv, **kw: subprocess.CompletedProcess(argv, rc, "", "e")):
                with self.assertRaises(RootError) as c:
                    Device().root("x")
            self.assertEqual(c.exception.returncode, rc)


class ImageShaTest(unittest.TestCase):
    def dev(self, out):
        class D(Device):
            def root(self, cmd):
                return "0\n" if "get-current-slot" in cmd else out
        return D()

    def header(self, magic=b"ANDROID!", ver=4):
        h = magic + bytes(32) + ver.to_bytes(4, "little")
        return h.hex()

    def test_ok(self):
        self.assertEqual(self.dev(f"{self.header()}\n{'ab' * 32}  -\n").running_image_sha(), "ab" * 32)

    def test_bad_magic_header_version_and_empty(self):
        for out in (f"{self.header(b'NOTADRD!')}\n{'ab' * 32}  -\n",
                    f"{self.header(ver=3)}\n{'ab' * 32}  -\n", "", "\n"):
            with self.assertRaises(ValueError, msg=out):
                self.dev(out).running_image_sha()
