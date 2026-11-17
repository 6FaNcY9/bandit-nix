"""Crawl public Telegram groups through their public post pages: no login, no account, read-only.

Admin status isn't visible on these pages, so every post is labelled as coming from any member."""
import argparse
import datetime
import html
import http.client
import re
import sys
import time
import urllib.error

from .crawl import Crawl, Finding, _wanted

SOURCES = ("WildKernelsTG", "BakaSU_Grp", "yurikernel")
LABEL = "someone's claim; any member, admin status unknown"
TOP = 2_000_000
PROBE = 8  # ids in a row can be deleted; a longer gap only makes the crawl start slightly older
DELAY = 0.5
MAX_ERRORS = 5
RETRIES = 4
TEXT = re.compile(r'<div class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>', re.S)
FILE = re.compile(r'class="tgme_widget_message_document_title[^"]*"[^>]*>(.*?)</div>', re.S)
DATE = re.compile(r'<time datetime="(\d{4}-\d\d-\d\d)')
LINK = re.compile(r'<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>', re.S)


def _plain(s):
    # link targets are often the useful part ("download here"), so keep them
    s = LINK.sub(lambda m: m[2] if m[1] in m[2] else f"{m[2]} ({m[1]})", s)
    s = re.sub(r"<br\s*/?>", "\n", s)
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()


def parse_post(page):
    """Return (date, text, files), or None when the page holds no post. Sender names are never read."""
    d = DATE.search(page)
    if not d or "tgme_widget_message_bubble" not in page:
        return None
    t = TEXT.search(page)
    return d[1], _plain(t[1]) if t else "", [_plain(f) for f in FILE.findall(page)]


_conn = None


def _get(path):
    global _conn
    if _conn is None:  # one reused connection: new ones sometimes stall for 15s, reused ones take 0.05s
        _conn = http.client.HTTPSConnection("t.me", timeout=30)
    _conn.request("GET", path, headers={"User-Agent": "Mozilla/5.0"})
    r = _conn.getresponse()
    body = r.read()
    if r.status != 200:
        raise urllib.error.HTTPError(path, r.status, r.reason, r.headers, None)
    return body.decode("utf-8", "replace")


def fetch_page(name, i):
    global _conn
    for attempt in range(RETRIES):
        try:
            return _get(f"/{name}/{i}?embed=1&mode=tme")
        except urllib.error.HTTPError:
            raise
        except (OSError, http.client.HTTPException) as e:  # one network blip must not lose a whole source
            if _conn:
                _conn.close()
            _conn = None
            if attempt == RETRIES - 1:
                raise OSError(f"{type(e).__name__}: {e}") from None
            time.sleep(10 * attempt)  # a server closing an idle connection is normal: retry at once


def newest(fetch, name, sleep=time.sleep):
    def alive(i):
        for j in range(i, i + PROBE):
            sleep(DELAY)
            if parse_post(fetch(name, j)):
                return j
        return 0
    lo, hi = alive(1), TOP
    if not lo:
        return 0
    while hi - lo > PROBE:
        mid = (lo + hi) // 2
        found = alive(mid)
        if found:
            lo = found
        else:
            hi = mid
    for j in range(hi + PROBE, lo, -1):  # the search stops within PROBE of the end
        sleep(DELAY)
        if parse_post(fetch(name, j)):
            return j
    return lo


def crawl_web(fetch=fetch_page, limit=2000, sources=SOURCES, sleep=time.sleep, progress=lambda *a: None, since=""):
    out = Crawl()
    for name in sources:
        try:
            top = newest(fetch, name, sleep)
        except urllib.error.HTTPError as e:
            out.not_read.append((name, f"HTTP {e.code} while finding the newest post"))
            continue
        except OSError as e:
            out.not_read.append((name, f"{type(e).__name__}: {str(e)[:80]}"))
            continue
        if not top:
            out.not_read.append((name, "no public posts found; it may be a person, a bot or private"))
            continue
        errors = 0
        for n, i in enumerate(range(top, max(top - limit, 0), -1)):
            if n % 200 == 0:
                progress(name, n, out)
            sleep(DELAY)
            try:
                post = parse_post(fetch(name, i))
                errors = 0
            except urllib.error.HTTPError as e:
                if e.code != 429:
                    errors += 1
                    if errors < MAX_ERRORS:
                        continue
                wait = (e.headers.get("Retry-After") if e.headers else None) or "unknown"
                out.cut_short.append((name, wait))
                break
            except OSError:
                errors += 1
                if errors >= MAX_ERRORS:
                    out.cut_short.append((name, "unknown; repeated network errors"))
                    break
                continue
            if post and post[0] < since:  # posts run newest first, so the rest are older still
                break
            if post and _wanted(post[1], post[2]):
                out.findings.append(Finding(name, post[0], f"https://t.me/{name}/{i}", post[1][:500], post[2], LABEL))
    return out


def main(args):
    p = argparse.ArgumentParser(prog="pkt crawl-web")
    p.add_argument("--limit", type=int, default=2000)
    p.add_argument("--days", type=int, default=14, help="stop at posts older than this")
    p.add_argument("--source", choices=SOURCES)
    a = p.parse_args(args)
    from .crawl import default_path, write_report
    path = default_path()
    if a.source:
        path = path[:-3] + f"-{a.source}.md"
    since = (datetime.date.today() - datetime.timedelta(days=a.days)).isoformat()

    def progress(source, n, c):  # a long run can be killed by Android, so keep what's collected
        print(f"{source}: {n} read, {len(c.findings)} kept", file=sys.stderr, flush=True)
        write_report(c, path)
    c = crawl_web(limit=a.limit, sources=(a.source,) if a.source else SOURCES, progress=progress, since=since)
    write_report(c, path)
    print(f"{len(c.findings)} findings; report: {path}")
    return 0
