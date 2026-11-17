import unittest
import urllib.error
from unittest import mock

from pkt import webcrawl as w


def page(text="", when="2026-11-01", doc=None, author="SECRETNAME"):
    d = f'<div class="tgme_widget_message_document_title accent_color" dir="auto">{doc}</div>' if doc else ""
    return (f'<div class="tgme_widget_message_bubble"><span class="tgme_widget_message_author_name">{author}</span>'
            f'<div class="tgme_widget_message_text js-message_text" dir="auto">{text}</div>{d}'
            f'<time datetime="{when}T01:02:03+00:00" class="datetime">x</time></div>')


GONE = "<html><body>no post</body></html>"


def site(posts, top=None):
    def fetch(name, i):
        v = posts.get(name, {}).get(i)
        if isinstance(v, Exception):
            raise v
        if v is not None:
            return v
        return page("chat") if top and i <= top.get(name, 0) else GONE
    return fetch


def nosleep(_):
    pass


class WebCrawlTests(unittest.TestCase):
    def test_parse_keeps_text_links_files_and_drops_sender(self):
        d, t, f = w.parse_post(page('New &amp; <a href="https://x.io/a">kernel</a><br/>line', doc="k.zip"))
        self.assertEqual(d, "2026-11-01")
        self.assertEqual(t, "New & kernel (https://x.io/a)\nline")
        self.assertEqual(f, ["k.zip"])
        self.assertNotIn("SECRETNAME", t)

    def test_missing_post_is_none(self):
        self.assertIsNone(w.parse_post(GONE))

    def test_newest_survives_gaps(self):
        gaps = {"g": {i: GONE for i in range(1000, 1020)}}
        self.assertEqual(w.newest(site(gaps, {"g": 5000}), "g", nosleep), 5000)

    def test_keeps_relevant_excludes_keybox_and_labels(self):
        posts = {"g": {50: page("new BakaSU kernel"), 49: page("lunch"), 48: page("free KEYBOX kernel"),
                       47: page("root", doc="x.xml")}}
        r = w.crawl_web(site(posts, {"g": 50}), limit=10, sources=("g",), sleep=nosleep)
        got = {f.link: f for f in r.findings}
        self.assertEqual(set(got), {"https://t.me/g/50"})
        self.assertIn("any member", got["https://t.me/g/50"].label)

    def test_limit_respected(self):
        real = w.newest
        w.newest = lambda *a: 100
        self.addCleanup(setattr, w, "newest", real)
        calls = []
        f = site({}, {"g": 100})

        def fetch(n, i):
            calls.append(i)
            return f(n, i)
        w.crawl_web(fetch, limit=3, sources=("g",), sleep=nosleep)
        self.assertEqual(calls, [100, 99, 98])

    def test_unreadable_source_is_reported_and_others_kept(self):
        posts = {"g": {i: page("kernel") for i in range(1, 6)}}
        r = w.crawl_web(site(posts), limit=5, sources=("nobody", "g"), sleep=nosleep)
        self.assertEqual([s for s, _ in r.not_read], ["nobody"])
        self.assertEqual(len(r.findings), 5)

    def test_stops_at_posts_older_than_since(self):
        real = w.newest
        w.newest = lambda *a: 10
        self.addCleanup(setattr, w, "newest", real)
        posts = {"g": {10: page("kernel", when="2026-11-02"), 9: page("kernel", when="2026-10-01"),
                       8: page("kernel", when="2026-11-02")}}
        r = w.crawl_web(site(posts), limit=5, sources=("g",), sleep=nosleep, since="2026-10-20")
        self.assertEqual([f.link for f in r.findings], ["https://t.me/g/10"])

    def test_network_blip_is_retried_on_a_new_connection(self):
        w._conn = None
        self.addCleanup(setattr, w, "_conn", None)
        bad, good = mock.MagicMock(), mock.MagicMock()
        bad.request.side_effect = OSError("dns")
        good.getresponse.return_value = mock.MagicMock(status=200, read=lambda: b"page")
        with mock.patch("pkt.webcrawl.time.sleep"), \
                mock.patch("pkt.webcrawl.http.client.HTTPSConnection", side_effect=[bad, good]):
            self.assertEqual(w.fetch_page("g", 1), "page")
        bad.close.assert_called_once()

    def test_http_error_status_is_raised(self):
        w._conn = None
        self.addCleanup(setattr, w, "_conn", None)
        c = mock.MagicMock()
        c.getresponse.return_value = mock.MagicMock(status=429, reason="slow", headers={"Retry-After": "9"}, read=lambda: b"")
        with mock.patch("pkt.webcrawl.http.client.HTTPSConnection", return_value=c), \
                self.assertRaises(urllib.error.HTTPError) as e:
            w.fetch_page("g", 1)
        self.addCleanup(e.exception.close)
        self.assertEqual(e.exception.code, 429)

    def test_rate_limit_stops_source_and_keeps_findings(self):
        err = urllib.error.HTTPError("u", 429, "slow", {"Retry-After": "60"}, None)
        self.addCleanup(err.close)
        posts = {"g": {10: page("kernel"), 9: err}}
        real = w.newest
        w.newest = lambda *a: 10
        self.addCleanup(setattr, w, "newest", real)
        r = w.crawl_web(site(posts, {"g": 10}), limit=5, sources=("g",), sleep=nosleep)
        self.assertEqual(len(r.findings), 1)
        self.assertEqual(r.cut_short, [("g", "60")])
