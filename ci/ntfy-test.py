"""Exercise the real first-start seed and ntfy ACLs in a disposable directory."""
import base64
import os
from pathlib import Path
import socket
import stat
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

with tempfile.TemporaryDirectory() as tmp:
    state = Path(tmp) / "mcbots"
    state.mkdir(mode=0o700)
    seed = Path(sys.argv[1]).read_text().replace("/var/lib/mcbots", str(state))
    subprocess.run(["bash", "-euo", "pipefail", "-c", "umask 077\n" + seed], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    credentials = state / "ntfy"
    before = {p.name: p.read_bytes() for p in credentials.iterdir()}
    subprocess.run(["bash", "-euo", "pipefail", "-c", "umask 077\n" + seed], check=True)
    assert before == {p.name: p.read_bytes() for p in credentials.iterdir()}, "restart rotated credentials"
    assert stat.S_IMODE(credentials.stat().st_mode) == 0o700
    assert all(stat.S_IMODE(p.stat().st_mode) == 0o600 for p in credentials.iterdir())
    env = dict(os.environ)
    for line in (credentials / "server.env").read_text().splitlines():
        key, value = line.split("=", 1)
        env[key] = value
    token = (credentials / "publisher.env").read_text().strip().split("=", 1)[1]
    password = (credentials / "read-credentials").read_text().split("Password: ", 1)[1].strip()
    auth = {"writer": "Bearer " + token,
            "reader": "Basic " + base64.b64encode(("phone:" + password).encode()).decode()}
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    env.update(NTFY_LISTEN_HTTP=f"127.0.0.1:{port}", NTFY_AUTH_FILE=tmp + "/user.db",
               NTFY_CACHE_FILE=tmp + "/cache.db", NTFY_ATTACHMENT_CACHE_DIR=tmp + "/attachments",
               NTFY_UPSTREAM_BASE_URL="")
    def request(path, who=None, data=None):
        headers = {"Authorization": auth[who]} if who else {}
        try:
            with urlopen(Request(f"http://127.0.0.1:{port}" + path, data=data, headers=headers), timeout=2) as r:
                return r.status, r.read()
        except HTTPError as e:
            return e.code, b""
    with open(tmp + "/server.log", "wb") as log:
        proc = subprocess.Popen(["ntfy", "serve", "--config", sys.argv[2]], env=env,
                                stdout=log, stderr=log)
        try:
            for _ in range(100):
                try:
                    if request("/v1/health")[0] == 200:
                        break
                except URLError:
                    pass
                assert proc.poll() is None, "ntfy exited during first-start provisioning"
                time.sleep(0.05)
            else:
                raise AssertionError("ntfy did not start")
            for who in (None, "reader"):
                assert request("/mcbots", who, b"fixture")[0] == 403, "unauthorized publish allowed"
            for who in (None, "writer"):
                assert request("/mcbots/json?poll=1", who)[0] == 403, "unauthorized read allowed"
            for who in ("writer", "reader"):
                assert request("/other", who, b"fixture")[0] == 403, "other topic publish allowed"
                assert request("/other/json?poll=1", who)[0] == 403, "other topic read allowed"
            assert request("/mcbots", "writer", b"fixture")[0] == 200
            status, body = request("/mcbots/json?poll=1", "reader")
            assert status == 200 and b'"message":"fixture"' in body, "reader did not receive published message"
        finally:
            proc.terminate()
            proc.wait(timeout=5)
    assert token.encode() not in Path(tmp + "/server.log").read_bytes(), "token appeared in logs"
print("ntfy seed persistence, modes, and deny-all/topic ACLs passed")
