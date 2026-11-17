from datetime import datetime, timezone
from types import SimpleNamespace

from telethon.tl.types import Channel, ChatPhotoEmpty


def FakeChannel(id):
    # real telethon type so get_peer_id gives the real negative form
    return Channel(id=id, title="t", photo=ChatPhotoEmpty(), date=datetime(2026, 1, 1), megagroup=True)


def msg(id, text="", sender=1, files=()):
    # files: names; the fake exposes only the first as .file
    f = SimpleNamespace(name=files[0]) if files else None
    return SimpleNamespace(id=id, message=text, sender_id=sender, file=f,
                           date=datetime(2026, 11, 1, tzinfo=timezone.utc))


class FakeClient:
    def __init__(self, sources, admins=None, raises=None):
        self.sources = sources          # name -> (entity, [messages]) or Exception
        self.admins = admins or {}      # name -> [ids] or Exception
        self.raises = raises or {}      # name -> exception raised after N messages: (n, exc)
        self.downloads = 0
        self.asked = []
        self.flood_sleep_threshold = None
        self.logged_out = False
        self.logout_result = True   # False, or an exception instance to raise
        self.disconnected = False

    async def start(self):
        pass

    async def log_out(self):
        self.logged_out = True
        if isinstance(self.logout_result, Exception):
            raise self.logout_result
        return self.logout_result

    async def disconnect(self):
        self.disconnected = True

    async def download_media(self, *a, **k):
        self.downloads += 1

    async def get_entity(self, name):
        s = self.sources[name]
        if isinstance(s, Exception):
            raise s
        return s[0]

    def _name(self, entity):
        return next(n for n, s in self.sources.items() if not isinstance(s, Exception) and s[0] is entity)

    async def iter_participants(self, entity, filter=None):
        a = self.admins.get(self._name(entity), [])
        if isinstance(a, Exception):
            raise a
        for i in a:
            yield SimpleNamespace(id=i)

    async def iter_messages(self, entity, limit=None):
        name = self._name(entity)
        self.asked.append((name, limit))
        for n, m in enumerate(self.sources[name][1]):
            if limit is not None and n >= limit:
                return
            if name in self.raises and n == self.raises[name][0]:
                raise self.raises[name][1]
            yield m
