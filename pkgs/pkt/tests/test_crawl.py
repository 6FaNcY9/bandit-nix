import asyncio
import os
import tempfile
import unittest

from pkt import crawl as cr
from tests.fake_tg import FakeChannel, FakeClient, msg


class FloodWait(Exception):
    seconds = 90


def run(c, **k):
    return asyncio.run(cr.crawl(c, **k))


def one(msgs, name="WildKernelsTG", **k):
    return FakeClient({name: (FakeChannel(7), msgs)}, **k)


class CrawlTests(unittest.TestCase):
    def test_keeps_relevant_posts(self):
        r = run(one([msg(1, "New BAKASU build"), msg(2, "lunch"), msg(3, "", files=["Kernel-5.10.zip"])]),
                sources={"WildKernelsTG": "all"})
        self.assertEqual([f.link for f in r.findings],
                         ["https://t.me/WildKernelsTG/1", "https://t.me/WildKernelsTG/3"])
        self.assertEqual(r.findings[1].files, ["Kernel-5.10.zip"])

    def test_excludes_keybox_posts(self):
        r = run(one([msg(1, "kernel KeyBox here"), msg(2, "kernel", files=["Keybox.XML"]),
                     msg(3, "kernel", files=["a.xml"]), msg(4, "kernel YuriKey"),
                     msg(5, "kernel", files=["KEYBOX-kernel.zip"])]),
                sources={"WildKernelsTG": "all"})
        self.assertEqual(r.findings, [])

    def test_no_sender_names_in_report(self):
        r = run(one([msg(1, "kernel ok", sender=424242)]), sources={"WildKernelsTG": "all"})
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.md")
            cr.write_report(r, p)
            with open(p) as fh:
                t = fh.read()
        self.assertNotIn("424242", t)
        self.assertIn("untrusted", t)
        self.assertIn("someone's claim", t)

    def test_downloads_nothing(self):
        c = one([msg(1, "kernel", files=["k.zip"])])
        run(c, sources={"WildKernelsTG": "all"})
        self.assertEqual(c.downloads, 0)

    def test_limit_respected(self):
        c = one([msg(i, "kernel") for i in range(10)])
        r = run(c, limit=3, sources={"WildKernelsTG": "all"})
        self.assertEqual(len(r.findings), 3)
        self.assertEqual(c.asked, [("WildKernelsTG", 3)])

    def test_labels_are_claims(self):
        r = run(one([msg(1, "kernel")]), sources={"WildKernelsTG": "all"})
        self.assertEqual({f.label for f in r.findings}, {"someone's claim"})

    def test_text_truncated_and_cannot_break_out(self):
        c = one([msg(1, "kernel\n# Heading\n```\n- [x](http://e)\r" + "a" * 600)])
        r = run(c, sources={"WildKernelsTG": "all"})
        self.assertEqual(len(r.findings[0].text), 500)
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.md")
            cr.write_report(r, p)
            with open(p) as fh:
                lines = fh.read().split("\n")
        body = lines[lines.index("> kernel"):]
        quoted = [l for l in body[:5]]
        self.assertTrue(all(l.startswith(">") for l in quoted), quoted)

    def test_post_text_is_cleaned_in_the_report(self):
        c = one([msg(1, "kernel \x1b[31mred\x1b[0m\u202eevil\rnext\x07 ok\nline2")])
        r = run(c, sources={"WildKernelsTG": "all"})
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.md")
            cr.write_report(r, p)
            with open(p, encoding="utf-8") as fh:
                t = fh.read()
        for bad in ("\x1b", "\r", "\x07", "\u202e"):
            self.assertNotIn(bad, t)
        self.assertIn("> kernel ?[31mred?[0m?evil", t)
        self.assertIn("> next? ok", t)

    def test_non_admin_group_post_ignored(self):
        c = one([msg(1, "kernel from member", sender=5), msg(2, "kernel from admin", sender=9),
                 msg(3, "kernel anon admin", sender=-1000000000007)], name="BakaSU_Grp", admins={"BakaSU_Grp": [9]})
        r = run(c, sources={"BakaSU_Grp": "admins"})
        self.assertEqual([f.link.rsplit("/", 1)[1] for f in r.findings], ["2", "3"])

    def test_admin_list_failure_reads_nothing(self):
        c = one([msg(1, "kernel")], name="BakaSU_Grp", admins={"BakaSU_Grp": RuntimeError("no")})
        r = run(c, sources={"BakaSU_Grp": "admins"})
        self.assertEqual(r.findings, [])
        self.assertEqual(c.asked, [])
        self.assertEqual(r.not_read[0][0], "BakaSU_Grp")

    def test_unreadable_source_skipped_others_kept(self):
        c = FakeClient({"yurikernel": ValueError("nope"), "WildKernelsTG": (FakeChannel(7), [msg(1, "kernel")])})
        r = run(c, sources={"yurikernel": "all", "WildKernelsTG": "all"})
        self.assertEqual(len(r.findings), 1)
        self.assertEqual([n for n, _ in r.not_read], ["yurikernel"])

    def test_non_channel_skipped(self):
        c = FakeClient({"yurikernel": (object(), [msg(1, "kernel")])})
        r = run(c, sources={"yurikernel": "all"})
        self.assertEqual(r.findings, [])
        self.assertEqual(r.not_read[0][0], "yurikernel")

    def test_flood_wait_stops_with_message(self):
        c = FakeClient({"WildKernelsTG": (FakeChannel(7), [msg(1, "kernel"), msg(2, "kernel")]),
                        "BakaSU_Grp": (FakeChannel(8), [msg(3, "kernel")])},
                       raises={"WildKernelsTG": (1, FloodWait())}, admins={"BakaSU_Grp": [1]})
        r = run(c, sources={"WildKernelsTG": "all", "BakaSU_Grp": "admins"}, flood_errors=(FloodWait,))
        self.assertEqual(len(r.findings), 2)
        self.assertEqual(r.cut_short, [("WildKernelsTG", 90)])
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.md")
            cr.write_report(r, p)
            with open(p) as fh:
                t = fh.read()
        self.assertIn("cut short", t)
        self.assertIn("90", t)

    def test_same_day_rerun_replaces_file(self):
        r = run(one([msg(1, "kernel")]), sources={"WildKernelsTG": "all"})
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.md")
            cr.write_report(r, p)
            cr.write_report(r, p)
            self.assertEqual(os.listdir(d), ["r.md"])
