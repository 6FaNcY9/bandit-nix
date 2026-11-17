import contextlib
import dataclasses
import io
import json
import os
import pathlib
import tempfile
import unittest
import zipfile
from unittest import mock

from pkt import cli, github, zipcheck
from pkt.state import State
from tests.test_zipcheck import Dev, image

CAND = dict(name="5.10.269-android12-2026-10-BakaSU-AnyKernel3.zip", version=[5, 10, 269], source="github",
            url="https://example.invalid/k.zip", sha256="aa", verified=True, path=None)


def run(fn, *a):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = fn(*a)
    return rc, out.getvalue()


class CliBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = State(path=os.path.join(self.tmp.name, "state.json"))

    def write_cands(self, cands):
        with open(cli.candidates_path(self.state), "w") as f:
            json.dump(cands, f)

    def zip(self, **kw):
        p = os.path.join(self.tmp.name, "k.zip")
        with zipfile.ZipFile(p, "w") as z:
            z.writestr("Image", image(**kw))
            z.writestr("anykernel.sh", "echo \x1b[31mred ‮evil\n")
        return p


class FindCmdTest(CliBase):
    def cands(self, *versions):
        return [github.Candidate(f"5.10.{v}-android12-lts-BakaSU-AnyKernel3.zip", (5, 10, v), "github",
                                 "https://x", "aa", True, None) for v in versions]

    def test_saves_candidates_and_hides_older(self):
        with mock.patch.object(github, "find", return_value=self.cands(272, 269, 252)):
            rc, out = run(cli.find_cmd, Dev(), self.state)
        saved = json.loads(pathlib.Path(cli.candidates_path(self.state)).read_text())
        self.assertEqual([c["version"] for c in saved], [[5, 10, 272], [5, 10, 269]])
        self.assertIn("1. 5.10.272", out)
        self.assertNotIn("252", out)

    def test_empty_messages_differ(self):
        with mock.patch.object(github, "find", return_value=[]):
            self.assertIn("upstream", run(cli.find_cmd, Dev(), self.state)[1])
        with mock.patch.object(github, "find", return_value=self.cands(252)):
            self.assertIn("all older", run(cli.find_cmd, Dev(), self.state)[1])


class CheckCmdTest(CliBase):
    def test_clean_exit_codes(self):
        rc, out = run(cli.check_cmd, Dev(), self.state, self.zip())
        self.assertEqual(rc, 3)  # uapi is always unknown
        self.assertIn("compatible, 1 unknown (needs confirmation)", out)

    def test_reject_exit_code(self):
        rc, out = run(cli.check_cmd, Dev(), self.state, self.zip(markers=[]))
        self.assertEqual(rc, 1)
        self.assertIn("result: rejected", out)

    def test_sanitizes_script(self):
        _, out = run(cli.check_cmd, Dev(), self.state, self.zip())
        self.assertNotIn("\x1b", out)
        self.assertNotIn("‮", out)

    def test_digit_named_existing_file_is_a_path(self):
        p = self.zip()
        d = os.path.join(self.tmp.name, "123")
        os.rename(p, d)
        cwd = os.getcwd()
        os.chdir(self.tmp.name)
        try:
            rc, out = run(cli.check_cmd, Dev(), self.state, "123")
        finally:
            os.chdir(cwd)
        self.assertIn("file: 123", out)

    def test_unverified_candidate_is_flagged(self):
        z = self.zip()
        self.write_cands([dict(CAND, sha256=None, verified=False)])
        with mock.patch.object(github, "download", return_value=z):
            rc, out = run(cli.check_cmd, Dev(), self.state, "1")
        self.assertIn("UNVERIFIED DOWNLOAD", out)
        self.assertIn("digest not verified", out)
        self.assertEqual(rc, 3)

    def test_malformed_and_unsafe_candidates(self):
        for bad, word in (([{"name": "x"}], "malformed"),
                          ([dict(CAND, url="http://x/k.zip")], "https"),
                          ([dict(CAND, url="file:///etc/passwd")], "https"),
                          ([dict(CAND, name="../evil.zip")], "name")):
            self.write_cands(bad)
            with self.assertRaises(RuntimeError, msg=word) as cm:
                cli.check_cmd(Dev(), self.state, "1")
            self.assertIn(word, str(cm.exception))
        with self.assertRaises(RuntimeError):
            cli.check_cmd(Dev(), self.state, "9")


class StatusTest(unittest.TestCase):
    def test_capabilities_line(self):
        class D(Dev):
            def current_slot(self): return "a"
            def caps_full(self): return True
        with mock.patch.object(cli, "getprop", return_value="_a"):
            _, out = run(cli.status, D(), State())
        self.assertIn("full capabilities: True", out)


class GetpropMissing(unittest.TestCase):
    def test_missing_getprop_gives_empty(self):
        # Outside Android (Nix build sandbox, a chroot without /system/bin) the
        # caller prints "unavailable" instead of crashing.
        with mock.patch.dict(os.environ, {"PATH": "/nonexistent"}):
            self.assertEqual(cli.getprop("ro.boot.slot_suffix"), "")
