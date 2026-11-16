"""Tests for pong-api: run with `python3 -I -m unittest discover -s hosts/pong/api` from Termux."""

import importlib.machinery
import importlib.util
import os
import pathlib
import tempfile
import threading
import unittest

HERE = pathlib.Path(__file__).resolve().parent
loader = importlib.machinery.SourceFileLoader("pong_api", str(HERE / "pong-api"))
spec = importlib.util.spec_from_loader("pong_api", loader)
pong_api = importlib.util.module_from_spec(spec)
loader.exec_module(pong_api)


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        d = pathlib.Path(self.dir.name)
        self.bin = d / "bin"
        self.bin.mkdir()
        echo = self.bin / "termux-echo"
        echo.write_text('#!/bin/sh\necho "out:$*"\necho "err" >&2\ncat\nexit 3\n')
        echo.chmod(0o755)
        self.sock = str(d / "api.sock")
        self.server = pong_api.make_server(self.sock, str(self.bin))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.dir.cleanup()

    def test_runs_command_with_args_stdin_and_status(self):
        rc, out, err = pong_api.call(self.sock, ["termux-echo", "a b", "c"], b"piped\n")
        self.assertEqual(rc, 3)
        self.assertEqual(out, b"out:a b c\npiped\n")
        self.assertEqual(err, b"err\n")

    def test_socket_is_private(self):
        self.assertEqual(os.stat(self.sock).st_mode & 0o777, 0o600)

    def test_rejects_names_outside_termux_commands(self):
        for name in ["rm", "../termux-echo", "termux-echo/../x", "/bin/sh"]:
            rc, out, err = pong_api.call(self.sock, [name], b"")
            self.assertEqual(rc, 126, name)
            self.assertIn(b"not allowed", err)

    def test_missing_command_is_127(self):
        rc, out, err = pong_api.call(self.sock, ["termux-nothere"], b"")
        self.assertEqual(rc, 127)

    def test_no_bridge_is_a_clear_error(self):
        rc, out, err = pong_api.call(self.sock + ".gone", ["termux-echo"], b"")
        self.assertEqual(rc, 69)
        self.assertIn(b"bridge not running", err)



class StdinTest(unittest.TestCase):
    def test_only_stdin_readers_get_stdin(self):
        self.assertTrue(pong_api.reads_stdin("termux-clipboard-set"))
        self.assertTrue(pong_api.reads_stdin("termux-share"))
        self.assertFalse(pong_api.reads_stdin("termux-battery-status"))
        self.assertTrue(pong_api.reads_stdin("termux-notification"))
        self.assertFalse(pong_api.reads_stdin("termux-wifi-connectioninfo"))

if __name__ == "__main__":
    unittest.main()
