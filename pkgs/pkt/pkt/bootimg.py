import hashlib
import os
import shutil
import subprocess

from .zipcheck import MAX_IMAGE


class BootImgError(RuntimeError):
    pass


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def _run(magiskboot, cwd, *args):
    # argv list, no shell; magiskboot is ours, the files are inside our own workdir
    try:
        r = subprocess.run([magiskboot, *args], cwd=cwd, capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise BootImgError(f"magiskboot {args[0]} failed: {e}")
    if r.returncode != 0:
        raise BootImgError(f"magiskboot {args[0]} failed ({r.returncode}): {(r.stderr or r.stdout).strip()[-300:]}")


def _unpack(magiskboot, boot, d):
    os.makedirs(d)
    _run(magiskboot, d, "unpack", os.path.abspath(boot))
    if not os.path.isfile(os.path.join(d, "kernel")):
        raise BootImgError("magiskboot found no kernel in the boot image")


def _head(path, n, off=0):
    with open(path, "rb") as f:
        f.seek(off)
        return f.read(n)


def check_source(d):
    """A real boot image has an arm64 kernel and a newc cpio ramdisk with its trailer.
    Anything else (for example a new image spliced over an old one) is refused."""
    k, r = os.path.join(d, "kernel"), os.path.join(d, "ramdisk.cpio")
    if _head(k, 4, 56) != b"ARMd":
        raise BootImgError("source boot image: kernel is not an arm64 Image (no ARMd at offset 56)")
    if not os.path.isfile(r) or _head(r, 6) != b"070701":
        raise BootImgError("source boot image: ramdisk is missing or not a newc cpio (no 070701)")
    size = os.path.getsize(r)
    if b"TRAILER!!!" not in _head(r, 4096, max(0, size - 4096)):
        raise BootImgError("source boot image: ramdisk cpio has no TRAILER!!! at its end")


def build_boot(image, source_boot, workdir, magiskboot):
    """Replace the kernel of source_boot with image; return the path of the new boot image.
    Never touches a partition. The result is unpacked again and compared before it is returned."""
    workdir, image, source_boot, magiskboot = (os.path.abspath(x) for x in (workdir, image, source_boot, magiskboot))
    src, out = os.path.join(workdir, "src"), os.path.join(workdir, "out")
    for d in (src, out):
        shutil.rmtree(d, ignore_errors=True)
    _unpack(magiskboot, source_boot, src)
    check_source(src)
    before = {n: sha(os.path.join(src, n)) for n in os.listdir(src) if n != "kernel"}
    shutil.copyfile(image, os.path.join(src, "kernel"))
    new = os.path.join(workdir, "new-boot.img")
    if os.path.exists(new):
        os.remove(new)
    _run(magiskboot, src, "repack", source_boot, new)
    if not os.path.isfile(new):
        raise BootImgError("magiskboot repack produced no image")
    size = os.path.getsize(new)
    if size > MAX_IMAGE:
        raise BootImgError(f"new boot image is {size} bytes, over the {MAX_IMAGE} limit")
    # trust nothing: unpack the result and compare every part
    _unpack(magiskboot, new, out)
    if sha(os.path.join(out, "kernel")) != sha(image):
        raise BootImgError("repacked kernel does not match the Image")
    after = {n: sha(os.path.join(out, n)) for n in os.listdir(out) if n != "kernel"}
    if before != after:
        diff = sorted(set(before) ^ set(after) | {n for n in before.keys() & after.keys() if before[n] != after[n]})
        raise BootImgError("repacked image differs from the original apart from the kernel: " + ", ".join(diff))
    return new
