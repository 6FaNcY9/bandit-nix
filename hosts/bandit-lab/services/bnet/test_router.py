"""Tests for the bnet router: worker choice, Ollama forwarding with retry, auth, fixed device list."""
import http.server
import json
import threading
import time
import urllib.error
import urllib.request

import pytest

import router

TOKEN = "lab-token"
AGENT_TOKEN = "agent-token"


def serve(handler_cls):
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler_cls)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_address[1]}"


def fake_agent(name, allowed=True, drop=False, calls=None):
    calls = calls if calls is not None else []

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _ok(self, body, code=200):
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            assert self.headers["Authorization"] == f"Bearer {AGENT_TOKEN}"
            calls.append(("GET", self.path))
            if self.path == "/state":
                return self._ok({"host": name, "state": "idle", "job_allowed": allowed, "job": None})
            if self.path.startswith("/ollama/"):
                return self._ok({"served_by": name})

        def do_POST(self):
            assert self.headers["Authorization"] == f"Bearer {AGENT_TOKEN}"
            n = int(self.headers.get("Content-Length") or 0)
            self.rfile.read(n)
            calls.append(("POST", self.path))
            if self.path == "/job/start":
                return self._ok({}, 200 if allowed else 409)
            if self.path.startswith("/ollama/"):
                if drop:
                    self.connection.close()  # worker vanished mid-request
                    return
                return self._ok({"served_by": name})

    return serve(H), calls


@pytest.fixture
def lab():
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _do(self):
            n = int(self.headers.get("Content-Length") or 0)
            self.rfile.read(n)
            data = json.dumps({"served_by": "bandit-lab"}).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = _do

    srv, url = serve(H)
    yield url
    srv.shutdown()


def make_router(devices, lab_url):
    r = router.Router(devices=devices, token=TOKEN, agent_token=AGENT_TOKEN, lab_ollama=lab_url)
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), r.handler())
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return r, f"http://127.0.0.1:{srv.server_address[1]}"


def call(url, method="GET", token=TOKEN, body=None):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, None


def test_pick_worker_prefers_order_and_skips_disallowed_and_stale():
    now = 1000.0
    order = ["albert", "slayer"]
    fresh = lambda allowed: {"job_allowed": allowed, "fetched": now - 3}
    assert router.pick_worker({"albert": fresh(True), "slayer": fresh(True)}, order, now) == "albert"
    assert router.pick_worker({"albert": fresh(False), "slayer": fresh(True)}, order, now) == "slayer"
    stale = {"job_allowed": True, "fetched": now - 16}
    assert router.pick_worker({"albert": stale, "slayer": fresh(False)}, order, now) is None
    assert router.pick_worker({}, order, now) is None


def test_request_goes_to_allowed_worker(lab):
    (srv, url), calls = fake_agent("albert")
    r, base = make_router([{"host": "albert", "kind": "pc", "agent": url}], lab)
    r.poll_once()
    code, body = call(base + "/api/generate", "POST", body={"model": "m", "prompt": "hi"})
    assert (code, body["served_by"]) == (200, "albert")
    assert ("POST", "/job/start") in calls
    assert ("POST", "/ollama/api/generate") in calls


def test_worker_refusing_job_falls_back_to_lab(lab):
    (srv, url), _ = fake_agent("albert", allowed=False)
    r, base = make_router([{"host": "albert", "kind": "pc", "agent": url}], lab)
    r.poll_once()
    assert call(base + "/api/generate", "POST", body={"model": "m"})[1]["served_by"] == "bandit-lab"


def test_worker_dropping_mid_request_is_retried_on_next(lab):
    (s1, u1), _ = fake_agent("albert", drop=True)
    (s2, u2), _ = fake_agent("slayer")
    devs = [{"host": "albert", "kind": "pc", "agent": u1}, {"host": "slayer", "kind": "pc", "agent": u2}]
    r, base = make_router(devs, lab)
    r.poll_once()
    code, body = call(base + "/api/generate", "POST", body={"model": "m"})
    assert (code, body["served_by"]) == (200, "slayer")


def test_wrong_or_missing_token_is_401_everywhere(lab):
    r, base = make_router([], lab)
    for path in ("/devices", "/api/tags"):
        assert call(base + path, token=None)[0] == 401
        assert call(base + path, token="nope")[0] == 401


def test_devices_lists_only_configured_hosts(lab):
    (srv, url), _ = fake_agent("albert")
    devs = [{"host": "albert", "kind": "pc", "agent": url}, {"host": "pong", "kind": "phone"}]
    r, base = make_router(devs, lab)
    r.tailnet_online = lambda: {"albert": True, "pong": False, "jerry": True}  # jerry is someone else's
    r.poll_once()
    code, body = call(base + "/devices")
    assert code == 200
    assert [d["host"] for d in body] == ["albert", "pong"]
    albert = body[0]
    assert albert["online"] is True and albert["state"] == "idle"
    assert body[1]["online"] is False and body[1]["state"] is None
