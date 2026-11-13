"""bnet router on bandit-lab.

Polls the bnet agents on the user's PCs, lists the user's devices, and serves an Ollama-compatible API
(/api/*) that runs each request on an idle PC when one may take it, otherwise on the lab's own Ollama.
Every endpoint needs the bearer token (it reveals who is at which PC).

Run: python3 router.py --devices devices.json --listen 100.125.161.81:47810 --lab-ollama http://127.0.0.1:11434
The token is read from $CREDENTIALS_DIRECTORY/token (systemd LoadCredential) or --token-file.
"""
import argparse
import hmac
import http.client
import http.server
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request

STALE_SEC = 15
POLL_SEC = 5
RELAY_ERRORS = (urllib.error.URLError, http.client.HTTPException, ConnectionError, TimeoutError, OSError)
# Only real work goes to the PCs; listing, pulling or deleting models always means the lab's own Ollama.
WORK_PATHS = ("/api/generate", "/api/chat", "/api/embed", "/api/embeddings")


def _model_key(name):
    return name if ":" in name else name + ":latest"


def pick_worker(states, order, now, exclude=(), model=None):
    """First host in config order whose fresh state allows a job and that has the model; None means: the lab."""
    for host in order:
        s = states.get(host)
        if host in exclude or not s:
            continue
        if now - s.get("fetched", 0) > STALE_SEC:
            continue
        if model and _model_key(model) not in {_model_key(m) for m in s.get("models") or []}:
            continue
        if s.get("job_allowed"):
            return host
    return None


class Router:
    def __init__(self, devices, token, agent_tokens, lab_ollama, timeout=3):
        self.devices = devices
        self.token = token
        self.agent_tokens = agent_tokens  # one per PC: a friend who reads his PC's token can't steer the other
        self.lab_ollama = lab_ollama.rstrip("/")
        self.timeout = timeout
        self.states = {}
        self.online = {}
        self.last_seen = {}
        self.lock = threading.Lock()

    # --- polling -------------------------------------------------------------------------------
    def tailnet_online(self):
        """{tailnet host name: online} from the local tailscale; empty when it cannot be read."""
        try:
            out = subprocess.run(["tailscale", "status", "--json"], capture_output=True, text=True, timeout=5).stdout
            st = json.loads(out)
        except (OSError, subprocess.SubprocessError, ValueError):
            return {}
        peers = list((st.get("Peer") or {}).values()) + [st.get("Self") or {}]
        return {p.get("HostName", "").lower(): bool(p.get("Online", True)) for p in peers if p.get("HostName")}

    def _agent(self, d, method, path, body=None, timeout=None):
        req = urllib.request.Request(d["agent"].rstrip("/") + path, method=method, data=body)
        req.add_header("Authorization", f"Bearer {self.agent_tokens[d['host']]}")
        if body is not None:
            req.add_header("Content-Type", "application/json")
        return urllib.request.urlopen(req, timeout=timeout or self.timeout)

    def poll_once(self):
        online = self.tailnet_online()
        now = time.time()
        states = {}
        for d in self.devices:
            if not d.get("agent"):
                continue
            try:
                with self._agent(d, "GET", "/state") as r:
                    states[d["host"]] = {**json.loads(r.read()), "fetched": now}
            except RELAY_ERRORS + (ValueError,):
                pass
        with self.lock:
            self.states = states
            self.online = online
            for d in self.devices:
                if self._is_online(d):
                    self.last_seen[d["host"]] = now

    def _is_online(self, d):
        return d["host"] in self.states or self.online.get(d.get("tailnet", d["host"]).lower(), False)

    def devices_view(self):
        with self.lock:
            out = []
            for d in self.devices:
                s = self.states.get(d["host"]) or {}
                seen = self.last_seen.get(d["host"])
                out.append({
                    "host": d["host"], "kind": d["kind"], "online": self._is_online(d),
                    "state": s.get("state"), "job": s.get("job"),
                    "last_seen": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(seen)) if seen else None,
                })
            return out

    # --- forwarding ----------------------------------------------------------------------------
    def open_upstream(self, method, path, body):
        """Response from the first worker that takes the request, else from the lab Ollama."""
        order = [d["host"] for d in self.devices if d.get("agent")] if path in WORK_PATHS else []
        by_host = {d["host"]: d for d in self.devices}
        try:
            model = json.loads(body or b"{}").get("model")
        except (ValueError, AttributeError):
            model = None
        tried = set()
        while True:
            with self.lock:
                host = pick_worker(self.states, order, time.time(), exclude=tried, model=model)
            if host is None:
                break
            tried.add(host)
            d = by_host[host]
            try:
                self._agent(d, "POST", "/job/start", b'{"kind":"ollama"}').close()
                return self._agent(d, method, "/ollama" + path, body, timeout=1800)
            except RELAY_ERRORS:
                # Refused (409), not ready or killed by the user returning (502), model gone (404), bad token:
                # whatever went wrong on this PC, the next PC or the lab answers instead. HTTPError is a URLError.
                pass
        req = urllib.request.Request(self.lab_ollama + path, method=method, data=body)
        if body is not None:
            req.add_header("Content-Type", "application/json")
        return urllib.request.urlopen(req, timeout=1800)

    def handler(self):
        router = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, fmt, *args):
                pass

            def _json(self, code, obj):
                data = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _authorized(self):
                got = self.headers.get("Authorization", "")
                return got.startswith("Bearer ") and hmac.compare_digest(got[7:].encode(), router.token.encode())

            def _dispatch(self):
                if not self._authorized():
                    return self._json(401, {"error": "unauthorized"})
                if self.command == "GET" and self.path == "/devices":
                    return self._json(200, router.devices_view())
                if self.path.startswith("/api/"):
                    n = int(self.headers.get("Content-Length") or 0)
                    body = self.rfile.read(n) if n else None
                    try:
                        up = router.open_upstream(self.command, self.path, body)
                    except urllib.error.HTTPError as e:
                        return self._json(e.code, {"error": str(e)})
                    except RELAY_ERRORS as e:
                        return self._json(502, {"error": f"no ollama reachable: {e}"})
                    with up:
                        self.send_response(up.status)
                        self.send_header("Content-Type", up.headers.get("Content-Type", "application/json"))
                        self.end_headers()  # HTTP/1.0: the body ends when we close, so streams relay as-is
                        while chunk := up.read1(65536) if hasattr(up, "read1") else up.read(65536):
                            self.wfile.write(chunk)
                            self.wfile.flush()
                    return
                return self._json(404, {"error": "not found"})

            do_GET = do_POST = do_DELETE = _dispatch

        return Handler


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--devices", required=True)
    ap.add_argument("--listen", required=True, help="host:port, the lab's Tailscale address")
    ap.add_argument("--lab-ollama", default="http://127.0.0.1:11434")
    ap.add_argument("--token-file", default=os.path.join(os.environ.get("CREDENTIALS_DIRECTORY", "/etc/bnet"), "token"))
    a = ap.parse_args()
    token = open(a.token_file).read().strip()
    devices = json.load(open(a.devices))
    cred = os.path.dirname(a.token_file)
    # $CREDENTIALS_DIRECTORY/agent-<host>: each PC's own token (systemd LoadCredential, see default.nix).
    agent_tokens = {d["host"]: open(os.path.join(cred, "agent-" + d["host"])).read().strip()
                    for d in devices if d.get("agent")}
    r = Router(devices, token=token, agent_tokens=agent_tokens, lab_ollama=a.lab_ollama)

    def poll():
        while True:
            r.poll_once()
            time.sleep(POLL_SEC)

    threading.Thread(target=poll, daemon=True).start()
    host, port = a.listen.rsplit(":", 1)
    http.server.ThreadingHTTPServer((host, int(port)), r.handler()).serve_forever()


if __name__ == "__main__":
    main()
