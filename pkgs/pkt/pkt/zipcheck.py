import dataclasses
import hashlib
import lzma
import re
import struct
import zipfile
import zlib

# Strings in the r22 BakaSU Image and absent from the ReSukiSU 5.10.269 Image (checked with strings/grep).
BAKASU_MARKERS = [
    b"ksu_uapi_version: %d",
    b"KSU_FEATURE_SHELL_SU_ADB_ONLY",
    b"shell_su_adb_only: set to %d",
    b"KSU_PREINIT=1",
]
MAX_IMAGE = 100663296
MIN_IMAGE = 16 * 1024 * 1024  # the real r22 GKI Image is 45 MB; anything under 16 MiB is not a kernel
READ_ERRORS = (zipfile.BadZipFile, OSError, NotImplementedError, RuntimeError, zlib.error, EOFError, lzma.LZMAError)
MAX_SCRIPT = 65536
# a banner must start at a string boundary (the byte before is not printable)
KERNEL_RE = re.compile(rb"(?<![\x20-\x7e])Linux version (5\.10\.(\d+))-android12(?![0-9])")
BANNER_RE = re.compile(rb"Linux version [\x20-\x7e]+")
KSU_RE = re.compile(rb"(?<![\x20-\x7e])v\d+\.\d+\.\d+[\w.-]*?-([0-9a-f]{8})(?:-dirty)?(?![\x20-\x7e])")
SUSFS_RE = re.compile(rb"susfs is initialized! version: v(\d+)\.(\d+)\.(\d+)")


@dataclasses.dataclass
class CheckResult:
    ok: bool
    rejects: list
    unknowns: list
    info: dict
    image_sha: str

    @property
    def needs_confirmation(self):
        return bool(self.unknowns)


def _read_image(z, info):
    h, parts, left = hashlib.sha256(), [], info.file_size
    with z.open(info) as f:
        while left > 0:
            chunk = f.read(min(1 << 20, left))
            if not chunk:
                break
            h.update(chunk)
            parts.append(chunk)
            left -= len(chunk)
    return b"".join(parts), h.hexdigest()


def _tuple(s):
    return tuple(int(x) for x in s.split("."))


def check_zip(path, dev, state):
    from .device import RootError
    rejects, unknowns, info, sha = [], [], {}, ""

    def done():
        return CheckResult(not rejects, rejects, unknowns, info, sha)

    def device(f):
        try:
            return f()
        except (RootError, ValueError, KeyError, TypeError, IndexError):
            return None

    try:
        z = zipfile.ZipFile(path)
    except (*READ_ERRORS, ValueError, struct.error) as e:  # a bad filename raises UnicodeDecodeError
        rejects.append(f"not a readable zip: {e}")
        return done()
    with z:
        # Only a member named exactly "Image" is read; nothing is extracted, so other names are irrelevant.
        images = [i for i in z.infolist() if i.filename == "Image"]
        if len(images) != 1:
            rejects.append("zip has no single member named Image")
            return done()
        if images[0].file_size > MAX_IMAGE:
            rejects.append(f"Image too large: declares {images[0].file_size} bytes, limit {MAX_IMAGE}")
            return done()
        try:
            data, sha = _read_image(z, images[0])
        except READ_ERRORS as e:
            rejects.append(f"cannot read Image: {type(e).__name__}: {e}")
            return done()
        if len(data) != images[0].file_size:
            rejects.append(f"Image is {len(data)} bytes but the zip declares {images[0].file_size}")
            return done()
        script = next((i for i in z.infolist() if i.filename == "anykernel.sh"), None)
        if script and script.file_size <= MAX_SCRIPT:
            try:
                info["anykernel.sh"] = z.read(script).decode(errors="replace")  # shown only, never run
            except READ_ERRORS:
                pass
    if len(data) < MIN_IMAGE or data[56:60] != b"ARMd":
        rejects.append("not an arm64 kernel Image (bad size or missing ARMd magic)")
        return done()

    m = KERNEL_RE.search(data)
    if not m:
        rejects.append("Image is not a 5.10.x android12 kernel")
        return done()
    version = m[1].decode()
    info["version"] = version
    info["banner"] = BANNER_RE.match(data, m.start())[0].decode().strip()  # the full /proc/version text
    if not all(mk in data for mk in BAKASU_MARKERS):
        rejects.append("Image does not carry the BakaSU markers (another root type?)")

    running = device(lambda: re.search(r"Linux version (\d+\.\d+\.\d+)", dev.real_kernel())[1])
    if running is None:
        unknowns.append("running kernel version unreadable")
    elif _tuple(version) < _tuple(running):
        rejects.append(f"older than the running kernel ({version} < {running})")

    # The Image only prints a format string for the uapi, so it can't be compared with ksud directly.
    ksud = device(dev.ksud_uapi)
    info["ksud_uapi"] = ksud
    unknowns.append(f"uapi: not readable from the Image (ksud reports {ksud if ksud is not None else 'unknown'})")
    # Partial check: the commit in the Image's KSU version vs ksud's. A newer build legitimately differs.
    km = KSU_RE.search(data)
    commit = km[1].decode() if km else None
    info["ksu_commit"] = commit
    ksud_commit = device(lambda: re.search(r"-g([0-9a-f]{8})", dev.ksud_version())[1])
    if commit is None or ksud_commit is None:
        unknowns.append("KSU commit unreadable (Image or ksud)")
    elif commit != ksud_commit:
        unknowns.append(f"KSU commit differs: Image {commit}, ksud {ksud_commit} "
                        "(common: the running r22 differs from ksud too, so this alone doesn't prove a problem)")

    installed = device(dev.susfs_version)
    sm = SUSFS_RE.search(data)
    if sm:
        info["susfs"] = "v" + b".".join(sm.groups()).decode()
    mm = re.match(r"v?(\d+)\.(\d+)", installed or "")
    if not sm or not mm:
        unknowns.append("susfs version unreadable (kernel or installed module)")
    elif (sm[1].decode(), sm[2].decode()) != mm.groups():
        rejects.append(f"susfs {info['susfs']} differs from installed module {installed} (major.minor)")

    if sha in state.bad_kernels:
        rejects.append("recorded as a bad kernel")
    running_sha = device(dev.running_image_sha)
    if running_sha is None:
        unknowns.append("running kernel hash unreadable")
    elif running_sha == sha:
        rejects.append("identical to the kernel already running")
    return done()
