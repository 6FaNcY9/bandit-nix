from types import SimpleNamespace
import asyncio
import contextlib
import sys
import io
import os
import tempfile
import unittest
from unittest import mock

from pkt import cli, tg
from tests.fake_tg import FakeChannel, FakeClient, msg


class TgTests(unittest.TestCase):
    def test_loose_permissions_refused(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "t.json")
            with open(p, "w") as f:
                f.write('{"api_id": 1, "api_hash": "abc"}')
            os.chmod(p, 0o644)
            with self.assertRaises(PermissionError):
                tg.load_credentials(p)
            os.chmod(p, 0o600)
            self.assertEqual(tg.load_credentials(p), (1, "abc"))

    def test_missing_file_prompts_without_echo(self):
        with mock.patch("pkt.tg.getpass.getpass", side_effect=["12", "hash"]) as g:
            self.assertEqual(tg.load_credentials("/nonexistent/x.json"), (12, "hash"))
        self.assertEqual(g.call_count, 2)

    def test_logout_called_on_exception(self):
        c = FakeClient({})

        async def run():
            async with tg.session(1, "h", factory=lambda *a: c):
                raise KeyboardInterrupt

        with self.assertRaises(KeyboardInterrupt):
            asyncio.run(run())
        self.assertTrue(c.logged_out)
        self.assertFalse(c.disconnected)
        self.assertEqual(c.flood_sleep_threshold, 0)

    def test_crawl_refuses_without_tty(self):
        with mock.patch("pkt.cli.istty", return_value=False), \
                mock.patch("pkt.cli.asyncio.run") as run, contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(cli.main(["crawl"]), 1)
        run.assert_not_called()
        self.assertIn("must be run by you in a terminal", err.getvalue())

    def test_no_credentials_in_output_or_state(self):
        c = FakeClient({n: (FakeChannel(i), [msg(1, "kernel")]) for i, n in enumerate(tg.CHANNELS)},
                       admins={"BakaSU_Grp": [1]})

        @contextlib.asynccontextmanager
        async def fake_session(*a):
            yield c

        out, err = io.StringIO(), io.StringIO()
        with tempfile.TemporaryDirectory() as d, \
                mock.patch("pkt.cli.istty", return_value=True), \
                mock.patch("pkt.tg.load_credentials", return_value=(987654321, "sEcReTh4sh")), \
                mock.patch("pkt.tg.session", fake_session), \
                mock.patch("pkt.crawl.default_path", return_value=os.path.join(d, "r.md")), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(cli.main(["crawl", "--limit", "5"]), 0)
            seen = out.getvalue() + err.getvalue() + "".join(
                open(os.path.join(d, f)).read() for f in os.listdir(d))
        for secret in ("sEcReTh4sh", "987654321"):
            self.assertNotIn(secret, seen)
        self.assertIn("r.md", out.getvalue())

    def _session_with(self, c, body=None):
        async def run():
            async with tg.session(1, "h", factory=lambda *a: c):
                if body:
                    raise body

        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            try:
                asyncio.run(run())
            except Exception:
                pass
        return err.getvalue()

    def test_unconfirmed_logout_disconnects_and_warns(self):
        for res in (False, RuntimeError("x")):
            c = FakeClient({})
            c.logout_result = res
            err = self._session_with(c)
            self.assertTrue(c.disconnected)
            self.assertIn("Devices", err)

    def test_disconnect_failure_does_not_mask_original_error(self):
        c = FakeClient({})
        c.logout_result = False

        async def bad():
            raise OSError("boom")
        c.disconnect = bad

        async def run():
            async with tg.session(1, "h", factory=lambda *a: c):
                raise ValueError("original")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(ValueError):
            asyncio.run(run())

    def test_code_delivery_is_shown(self):
        from telethon.tl.types.auth import SentCodeTypeSms, SentCodeTypeSetUpEmailRequired
        for kind, expected in ((SentCodeTypeSms(length=5), "SMS"),
                               (SentCodeTypeSetUpEmailRequired(), "SentCodeTypeSetUpEmailRequired")):
            sent = SimpleNamespace(type=kind, next_type=None, timeout=None)
            c = FakeClient({})

            async def send(phone, force_sms=False, _sent=sent):
                return _sent

            async def start(_c=c):
                self.assertIs(await _c.send_code_request("x"), sent)
            c.send_code_request, c.start = send, start

            async def go():
                async with tg.session(1, "h", factory=lambda *a: c):
                    pass
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                asyncio.run(go())
            self.assertIn(expected, err.getvalue())

    def test_failed_login_does_not_warn(self):
        c = FakeClient({})
        c.logout_result = False

        async def bad():
            raise ConnectionError("x")
        c.start = bad
        err = self._session_with(c)
        self.assertTrue(c.disconnected)
        self.assertEqual(err, "")

    def test_missing_telethon_checked_before_credentials(self):
        err = io.StringIO()
        with mock.patch("pkt.cli.istty", return_value=True), \
                mock.patch.dict(sys.modules, {"telethon": None}), \
                mock.patch("pkt.tg.load_credentials") as lc, \
                mock.patch("pkt.tg.getpass.getpass") as gp, \
                contextlib.redirect_stderr(err):
            self.assertEqual(cli.main(["crawl"]), 1)
        lc.assert_not_called()
        gp.assert_not_called()
        self.assertIn("pip install", err.getvalue())

    def test_run_error_is_short_message_no_traceback(self):
        def boom(coro):
            coro.close()  # the real asyncio.run consumes it; an unclosed one warns
            raise ConnectionError("down")
        err = io.StringIO()
        with mock.patch("pkt.cli.istty", return_value=True), \
                mock.patch("pkt.tg.load_credentials", return_value=(987654321, "sEcReTh4sh")), \
                mock.patch("pkt.cli.asyncio.run", side_effect=boom), \
                contextlib.redirect_stderr(err):
            self.assertEqual(cli.main(["crawl"]), 1)
        self.assertIn("ConnectionError: down", err.getvalue())
        self.assertNotIn("Traceback", err.getvalue())

    def test_bad_typed_api_id_not_echoed(self):
        err = io.StringIO()
        with mock.patch("pkt.cli.istty", return_value=True), \
                mock.patch("pkt.tg.CREDENTIALS", "/nonexistent/x.json"), \
                mock.patch("pkt.tg.load_credentials.__defaults__", ("/nonexistent/x.json",)), \
                mock.patch("pkt.tg.getpass.getpass", return_value="TYPEDsecret"), \
                contextlib.redirect_stderr(err):
            self.assertEqual(cli.main(["crawl"]), 1)
        self.assertNotIn("TYPEDsecret", err.getvalue())
        self.assertIn("number", err.getvalue())
