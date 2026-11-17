import contextlib
import dataclasses
import fcntl
import json
import os
import tempfile

PATH = os.path.expanduser("~/.local/state/pong-kernel-tool/state.json")


@dataclasses.dataclass
class State:
    baseline: dict | None = None
    b_booted_at: str | None = None
    known_good: str | None = None
    pending: dict | None = None
    bad_kernels: list = dataclasses.field(default_factory=list)
    last_backup: str | None = None
    bad_reasons: dict = dataclasses.field(default_factory=dict)  # image sha -> why; old files have none
    known_good_image: dict | None = None  # {slot, path, sha}: the verified image that booted on the known good slot
    rehearsal_passed: bool = False
    path: str = dataclasses.field(default=PATH, repr=False, compare=False)

    @classmethod
    def load(cls, path=PATH):
        try:
            with open(path) as f:
                data = json.load(f)
        except FileNotFoundError:
            return cls(path=path)
        # corrupt state raises (ValueError): never silently forget known_good
        if not isinstance(data, dict):
            raise ValueError(f"corrupt state file {path}")
        names = {f.name for f in dataclasses.fields(cls)} - {"path"}
        return cls(path=path, **{k: v for k, v in data.items() if k in names})

    def save(self):
        d = {k: v for k, v in dataclasses.asdict(self).items() if k != "path"}
        folder = os.path.dirname(self.path)
        os.makedirs(folder, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=folder, prefix=".state-", suffix=".tmp")  # unique: no two writers share it
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(d, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, self.path)
        except BaseException:
            with contextlib.suppress(OSError):
                os.remove(tmp)
            raise
        dfd = os.open(folder, os.O_RDONLY)  # make the rename itself durable
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)

    @contextlib.contextmanager
    def lock(self):
        """One pkt that changes things at a time."""
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path + ".lock", "w") as f:
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                raise RuntimeError("another pkt is running (state is locked)")
            yield
