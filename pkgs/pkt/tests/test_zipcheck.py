import hashlib
import os
import pathlib
import tempfile
import unittest
import zipfile
from unittest import mock

from pkt import zipcheck
from pkt.device import Device, RootError
from pkt.state import State

KERNEL = b"Linux version 5.10.269-android12-Wild (x) #1 SMP\0"
SUSFS = b"\x016susfs:[%u][%d][%s] susfs is initialized! version: v2.3.0 \0"


def image(version=b"5.10.269", susfs=SUSFS, markers=zipcheck.BAKASU_MARKERS, ksu=b"v4.2.0-rc3-516d3e87-dirty",
          header=True):
    body = (b"\0" * 64 + b"Linux version " + version + b"-android12-Wild (x) #1 SMP\0"
            + b"\0".join(markers) + b"\0" + ksu + b"\0" + susfs)
    if header:
        body = body[:56] + b"ARMd" + body[60:]
    return body.ljust(zipcheck.MIN_IMAGE, b"\0")


class Dev(Device):
    def __init__(self, kernel="Linux version 5.10.269-android12-Wild (x)", uapi=6,
                 susfs="v2.3.0-R28", running_sha="running", ksud="ksud 4.2.0-rc3-86-g516d3e87 (uapi: 6)"):
        self.v = dict(kernel=kernel, uapi=uapi, susfs=susfs, sha=running_sha, ksud=ksud)

    def _get(self, k):
        if self.v[k] is None:
            raise RootError(k)
        return self.v[k]

    def real_kernel(self):
        return self._get("kernel")

    def ksud_uapi(self):
        return self._get("uapi")

    def ksud_version(self):
        return self._get("ksud")

    def susfs_version(self):
        return self._get("susfs")

    def running_image_sha(self):
        return self._get("sha")


class ZipCheckBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def mkzip(self, members):
        p = os.path.join(self.tmp.name, "k.zip")
        with zipfile.ZipFile(p, "w") as z:
            for n, data in members.items():
                z.writestr(n, data)
        return p

    def check(self, members=None, dev=None, state=None):
        zp = self.mkzip(members if members is not None else {"Image": image()})
        return zipcheck.check_zip(zp, dev or Dev(), state or State())


class ZipCheckTest(ZipCheckBase):
    def test_good_zip_passes(self):
        img = image()
        r = self.check({"Image": img, "anykernel.sh": "echo hi\n"})
        self.assertEqual((r.ok, r.rejects), (True, []))
        self.assertEqual(r.image_sha, hashlib.sha256(img).hexdigest())
        self.assertEqual(r.info["version"], "5.10.269")
        self.assertEqual(r.info["susfs"], "v2.3.0")
        self.assertEqual(r.info["anykernel.sh"], "echo hi\n")
        self.assertTrue(any("uapi" in u for u in r.unknowns))
        self.assertTrue(r.needs_confirmation)
        self.assertEqual(r.info["ksu_commit"], "516d3e87")
        self.assertFalse(any("commit" in u for u in r.unknowns))

    def test_no_unknowns_means_no_confirmation_needed(self):
        r = zipcheck.CheckResult(True, [], [], {}, "x")
        self.assertFalse(r.needs_confirmation)

    def test_ksu_commit_mismatch_is_unknown_with_both_values(self):
        r = self.check({"Image": image(ksu=b"v4.2.0-rc3-d5e9e025-dirty")})
        self.assertTrue(r.ok)
        self.assertTrue(any("d5e9e025" in u and "516d3e87" in u for u in r.unknowns))

    def test_ksu_commit_absent_is_unknown(self):
        r = self.check({"Image": image(ksu=b"")})
        self.assertTrue(any("KSU commit unreadable" in u for u in r.unknowns))

    def test_markers_only_file_rejected(self):
        r = self.check({"Image": b"\0".join(zipcheck.BAKASU_MARKERS) + b"\0Linux version 5.10.269-android12-x\0"})
        self.assertFalse(r.ok)
        self.assertTrue(any("arm64 kernel Image" in x for x in r.rejects))

    def test_full_banner_is_recorded(self):
        r = self.check({"Image": image()})
        self.assertEqual(r.info["banner"], "Linux version 5.10.269-android12-Wild (x) #1 SMP")

    def test_missing_arm64_magic_rejected(self):
        r = self.check({"Image": image(header=False)})
        self.assertTrue(any("ARMd" in x for x in r.rejects))

    def test_banner_inside_a_longer_string_is_not_a_banner(self):
        img = image().replace(b"\0Linux version 5.10.269", b"xLinux version 5.10.269")
        self.assertTrue(any("5.10" in x for x in self.check({"Image": img}).rejects))

    def test_corrupt_member_rejected_not_crash(self):
        p = self.mkzip({"Image": image()})
        raw = bytearray(pathlib.Path(p).read_bytes())
        raw[200:260] = bytes(range(60))  # inside the deflate stream
        pathlib.Path(p).write_bytes(bytes(raw))
        r = zipcheck.check_zip(p, Dev(), State())
        self.assertFalse(r.ok)
        self.assertTrue(any("cannot read Image" in x for x in r.rejects))

    def test_truncated_zip_rejected_not_crash(self):
        p = self.mkzip({"Image": image()})
        raw = pathlib.Path(p).read_bytes()
        pathlib.Path(p).write_bytes(raw[: len(raw) // 2])
        self.assertFalse(zipcheck.check_zip(p, Dev(), State()).ok)

    def test_short_read_rejected(self):
        p = self.mkzip({"Image": image()})

        class Short:
            def __enter__(s): return s
            def __exit__(s, *a): pass
            def read(s, n, _d=[b"abc", b""]): return _d.pop(0)
        with mock.patch.object(zipfile.ZipFile, "open", return_value=Short()):
            r = zipcheck.check_zip(p, Dev(), State())
        self.assertTrue(any("declares" in x for x in r.rejects))

    def test_proc_version_without_match_is_unknown(self):
        r = self.check(dev=Dev(kernel="garbage"))
        self.assertTrue(r.ok)
        self.assertTrue(any("running kernel version" in u for u in r.unknowns))

    def test_no_image_rejected(self):
        r = self.check({"boot.img": b"x"})
        self.assertFalse(r.ok)
        self.assertTrue(any("Image" in x for x in r.rejects))

    def test_oversized_image_rejected_by_declared_size(self):
        p = self.mkzip({"Image": bytes(zipcheck.MAX_IMAGE + 1)})  # zeros: a tiny zip
        with mock.patch.object(zipfile.ZipFile, "open", side_effect=AssertionError("read the image")):
            r = zipcheck.check_zip(p, Dev(), State())
        self.assertTrue(any("large" in x for x in r.rejects))

    def test_traversal_names_ignored(self):
        r = self.check({"../Image": b"evil", "/abs/Image": b"evil", "sub/Image": b"evil"})
        self.assertFalse(r.ok)
        self.assertTrue(any("Image" in x for x in r.rejects))
        self.assertEqual(os.listdir(self.tmp.name), ["k.zip"])

    def test_traversal_next_to_good_image_still_reads_only_image(self):
        r = self.check({"../evil": b"evil", "Image": image()})
        self.assertTrue(r.ok)
        self.assertEqual(sorted(os.listdir(self.tmp.name)), ["k.zip"])

    def test_undecodable_member_name_rejected(self):
        p = os.path.join(self.tmp.name, "bad.zip")
        with zipfile.ZipFile(p, "w") as z:
            z.writestr("Image", b"x")
        with open(p, "rb") as fh:
            raw = fh.read().replace(b"Image", b"\xff\xffage")
        with open(p, "wb") as f:
            f.write(raw)
        r = zipcheck.check_zip(p, Dev(), State())
        self.assertTrue(r.rejects)

    def test_not_a_zip_rejected(self):
        p = os.path.join(self.tmp.name, "n.zip")
        with open(p, "wb") as f:
            f.write(b"not a zip")
        r = zipcheck.check_zip(p, Dev(), State())
        self.assertTrue(any("zip" in x for x in r.rejects))

    def test_missing_file_rejected(self):
        r = zipcheck.check_zip(os.path.join(self.tmp.name, "nope.zip"), Dev(), State())
        self.assertFalse(r.ok)

    def test_not_510_android12_rejected(self):
        r = self.check({"Image": image(version=b"5.15.1").replace(b"android12", b"android13")})
        self.assertTrue(any("5.10" in x for x in r.rejects))

    def test_not_bakasu_rejected(self):
        r = self.check({"Image": image(markers=[])})
        self.assertTrue(any("BakaSU" in x for x in r.rejects))

    def test_partial_markers_rejected(self):
        r = self.check({"Image": image(markers=zipcheck.BAKASU_MARKERS[:1])})
        self.assertTrue(any("BakaSU" in x for x in r.rejects))

    def test_older_rejected(self):
        r = self.check({"Image": image(version=b"5.10.252")})
        self.assertTrue(any("older" in x for x in r.rejects))

    def test_newer_ok(self):
        self.assertTrue(self.check({"Image": image(version=b"5.10.280")}).ok)

    def test_already_running_rejected(self):
        img = image()
        dev = Dev(running_sha=hashlib.sha256(img).hexdigest())
        r = self.check({"Image": img}, dev)
        self.assertTrue(any("running" in x for x in r.rejects))

    def test_bad_kernel_rejected(self):
        img = image()
        st = State(bad_kernels=[hashlib.sha256(img).hexdigest()])
        r = self.check({"Image": img}, state=st)
        self.assertTrue(any("bad" in x for x in r.rejects))

    def test_susfs_minor_mismatch_rejected(self):
        r = self.check(dev=Dev(susfs="v2.4.0-R30"))
        self.assertTrue(any("susfs" in x for x in r.rejects))

    def test_susfs_patch_difference_ok(self):
        self.assertTrue(self.check(dev=Dev(susfs="v2.3.9-R40")).ok)

    def test_unreadable_susfs_is_unknown(self):
        r = self.check({"Image": image(susfs=b"")})
        self.assertTrue(r.ok)
        self.assertTrue(any("susfs" in u for u in r.unknowns))
        r = self.check(dev=Dev(susfs=None))
        self.assertTrue(r.ok)
        self.assertTrue(any("susfs" in u for u in r.unknowns))

    def test_unreadable_device_values_are_unknown_not_pass(self):
        r = self.check(dev=Dev(kernel=None, uapi=None, running_sha=None))
        self.assertTrue(r.ok)
        for word in ("running kernel version", "uapi", "running kernel hash"):
            self.assertTrue(any(word in u for u in r.unknowns), word)
