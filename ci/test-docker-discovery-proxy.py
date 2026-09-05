"""Check the real HAProxy ACLs against an isolated Unix HTTP backend."""

from pathlib import Path
import shlex
import socket
import subprocess
import sys
import tempfile
import threading
import time


command = shlex.split(sys.argv[1])
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    frontend, backend = root / "frontend.sock", root / "backend.sock"
    config = root / "haproxy.cfg"
    config.write_text(Path(command[-1]).read_text()
                      .replace("/run/traefik-docker-proxy/docker.sock", str(frontend))
                      .replace("/var/run/docker.sock", str(backend)))
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(backend))
    server.listen()
    received = []

    def serve():
        while True:
            connection, _ = server.accept()
            with connection:
                request = connection.recv(8192)
                received.append(request.split(b"\r\n")[0])
                connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")

    threading.Thread(target=serve, daemon=True).start()
    subprocess.run([command[0], "-c", "-f", str(config)], check=True)
    process = subprocess.Popen([command[0], "-db", "-f", str(config)])
    try:
        for _ in range(100):
            if frontend.exists():
                break
            assert process.poll() is None, "HAProxy exited during startup"
            time.sleep(0.05)
        cases = [
            ("GET", "/_ping", 200),
            ("HEAD", "/_ping", 200),
            ("GET", "/version", 200),
            ("GET", "/v1.47/containers/json?all=1", 200),
            ("GET", "/v1.47/containers/abc123/json", 200),
            ("GET", "/v1.47/events?filters=%7B%7D", 200),
            ("POST", "/v1.47/containers/create", 403),
            ("POST", "/version", 403),
            ("GET", "/v1.47/containers/abc123/archive?path=/etc", 403),
            ("GET", "/v1.47/containers/abc123/logs", 403),
            ("GET", "/v1.47/images/json", 403),
            ("DELETE", "/v1.47/containers/abc123", 403),
        ]
        for method, path, expected in cases:
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(5)
                client.connect(str(frontend))
                client.sendall(f"{method} {path} HTTP/1.1\r\nHost: docker\r\nConnection: close\r\n\r\n".encode())
                response = client.recv(8192)
            assert int(response.split()[1]) == expected, (method, path, response)
        assert len(received) == sum(status == 200 for _, _, status in cases), received
        print(f"PASS: {len(cases)} Docker discovery API allow/deny cases")
    finally:
        process.terminate()
        process.wait(timeout=5)
