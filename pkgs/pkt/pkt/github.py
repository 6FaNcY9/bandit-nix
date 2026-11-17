import dataclasses
import hashlib
import json
import os
import re
import urllib.error
import urllib.request

API = "https://api.github.com/repos/WildKernels/GKI_KernelSU_SUSFS/releases?per_page=5"
MAX_DOWNLOAD = 150 * 1024 * 1024  # real zips are ~23 MB
ASSET = re.compile(r"^5\.10\.(\d+)-android12-(\d{4}-\d{2}|lts)-BakaSU-AnyKernel3\.zip$")


class GithubError(RuntimeError):
    pass


@dataclasses.dataclass
class Candidate:
    name: str
    version: tuple
    source: str
    url: str
    sha256: str | None
    verified: bool
    path: str | None


def fetch_http(url):
    req = urllib.request.Request(url, headers={"User-Agent": "pkt", "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")
    except OSError as e:
        raise GithubError(f"cannot reach GitHub: {e}")


def find(fetch=fetch_http):
    status, body = fetch(API)
    if status == 429 or (status == 403 and "rate limit" in body.lower()):
        raise GithubError("GitHub API rate limit reached (unauthenticated: 60 requests/hour); try again later")
    if status != 200:
        raise GithubError(f"GitHub API returned HTTP {status}")
    try:
        releases = json.loads(body)
    except ValueError:
        raise GithubError("GitHub API returned something that is not JSON")
    if not isinstance(releases, list) or not all(isinstance(r, dict) for r in releases):
        raise GithubError("GitHub API returned an unexpected shape (expected a list of releases)")
    releases = sorted((r for r in releases if not r.get("draft") and not r.get("prerelease")),
                      key=lambda r: r.get("published_at") or "", reverse=True)
    seen, out = set(), []
    for rel in releases:
        batch = []
        for a in rel.get("assets", []):
            m = ASSET.match(a.get("name", ""))
            if not m or a["name"] in seen:
                continue
            seen.add(a["name"])
            digest = a.get("digest") or ""
            sha = digest[7:] if digest.startswith("sha256:") else None
            batch.append(Candidate(a["name"], (5, 10, int(m[1])), "github", a["browser_download_url"],
                                   sha, sha is not None, None))
        out += sorted(batch, key=lambda c: (tuple(-n for n in c.version), c.name))
    return out


def download(c, dest_dir):
    # c.name was matched by ASSET, so it cannot contain a path separator
    path = os.path.join(dest_dir, c.name)
    h, size = hashlib.sha256(), 0
    try:
        with urllib.request.urlopen(c.url, timeout=60) as r, open(path, "wb") as f:
            while chunk := r.read(1 << 20):
                size += len(chunk)
                if size > MAX_DOWNLOAD:
                    raise GithubError(f"{c.name}: larger than {MAX_DOWNLOAD} bytes; file deleted")
                h.update(chunk)
                f.write(chunk)
    except (OSError, GithubError) as e:
        if os.path.exists(path):
            os.remove(path)
        raise e if isinstance(e, GithubError) else GithubError(f"download failed: {e}")
    if c.sha256 and h.hexdigest() != c.sha256.lower():
        os.remove(path)
        raise GithubError(f"{c.name}: sha256 does not match the release digest; file deleted")
    return path
