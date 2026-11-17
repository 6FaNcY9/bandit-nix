import hashlib
import json
import os
import pathlib
import tempfile
import unittest

from pkt import github

HERE = os.path.dirname(__file__)


def fetch_fixture(url):
    with open(os.path.join(HERE, "data", "releases.json")) as f:
        return 200, f.read()


class FindTest(unittest.TestCase):
    def test_filters_to_bakasu_510(self):
        names = [c.name for c in github.find(fetch_fixture)]
        self.assertEqual(names, [
            "5.10.269-android12-2026-10-BakaSU-AnyKernel3.zip",
            "5.10.269-android12-lts-BakaSU-AnyKernel3.zip",
            "5.10.252-android12-2026-04-BakaSU-AnyKernel3.zip",
            "5.10.240-android12-2025-12-BakaSU-AnyKernel3.zip",
        ])

    def test_newest_release_wins_and_digest_marks_verified(self):
        cs = github.find(fetch_fixture)
        self.assertEqual(cs[0].url, "https://example.invalid/r22/269-bakasu.zip")
        self.assertEqual((cs[0].sha256, cs[0].verified, cs[0].version, cs[0].source),
                         ("aa", True, (5, 10, 269), "github"))
        self.assertEqual((cs[1].sha256, cs[1].verified), (None, False))

    def test_rate_limit_gives_clear_error(self):
        with self.assertRaises(github.GithubError) as cm:
            github.find(lambda url: (403, '{"message": "API rate limit exceeded"}'))
        self.assertIn("rate limit", str(cm.exception))

    def test_plain_403_is_not_called_rate_limit(self):
        with self.assertRaises(github.GithubError) as cm:
            github.find(lambda url: (403, '{"message": "Forbidden"}'))
        self.assertNotIn("rate limit", str(cm.exception))
        self.assertIn("403", str(cm.exception))

    def test_non_list_200_is_clear_error(self):
        for body in ('{"a": 1}', "[1, 2]", "null"):
            with self.assertRaises(github.GithubError, msg=body):
                github.find(lambda url: (200, body))

    def test_other_http_error(self):
        with self.assertRaises(github.GithubError) as cm:
            github.find(lambda url: (500, "oops"))
        self.assertIn("500", str(cm.exception))


class DownloadTest(unittest.TestCase):
    def cand(self, d, data, sha):
        src = os.path.join(d, "src.bin")
        with open(src, "wb") as f:
            f.write(data)
        return github.Candidate("5.10.1-android12-2026-01-BakaSU-AnyKernel3.zip", (5, 10, 1),
                                "github", "file://" + src, sha, True, None)

    def test_download_ok(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "out")
            os.mkdir(out)
            c = self.cand(d, b"zipdata", hashlib.sha256(b"zipdata").hexdigest())
            p = github.download(c, out)
            self.assertEqual(p, os.path.join(out, c.name))
            self.assertEqual(pathlib.Path(p).read_bytes(), b"zipdata")

    def test_digest_mismatch_deletes_file(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "out")
            os.mkdir(out)
            c = self.cand(d, b"zipdata", "00" * 32)
            with self.assertRaises(github.GithubError):
                github.download(c, out)
            self.assertEqual(os.listdir(out), [])

    def test_uppercase_digest_matches(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "out")
            os.mkdir(out)
            c = self.cand(d, b"zipdata", hashlib.sha256(b"zipdata").hexdigest().upper())
            self.assertTrue(os.path.exists(github.download(c, out)))

    def test_size_cap_deletes_file(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "out")
            os.mkdir(out)
            c = self.cand(d, b"x" * 100, None)
            old, github.MAX_DOWNLOAD = github.MAX_DOWNLOAD, 50
            try:
                with self.assertRaises(github.GithubError) as cm:
                    github.download(c, out)
            finally:
                github.MAX_DOWNLOAD = old
            self.assertIn("larger", str(cm.exception))
            self.assertEqual(os.listdir(out), [])
