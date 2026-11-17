import os
import tempfile
import unittest
import zipfile

from pkt import bootimg

MB = os.environ.get("PKT_TEST_MAGISKBOOT")
BACKUPS = "/sdcard/Download/root-backups/20261104-013225-B4.1-260414-1749"
BOOT_B = os.path.join(BACKUPS, "boot_b.img")
ZIP = "/storage/emulated/0/Download/5.10.269-android12-2026-10-BakaSU-AnyKernel3.zip"


@unittest.skipUnless(MB and os.path.exists(MB) and os.path.exists(BOOT_B) and os.path.exists(ZIP),
                     "needs PKT_TEST_MAGISKBOOT, the boot_b backup and the r22 zip")
class RealBootImage(unittest.TestCase):
    def test_build_from_boot_b_and_r22_image(self):
        with tempfile.TemporaryDirectory() as t:
            image = os.path.join(t, "Image")
            with zipfile.ZipFile(ZIP) as z, open(image, "wb") as f:
                f.write(z.read("Image"))
            new = bootimg.build_boot(image, BOOT_B, os.path.join(t, "w"), MB)
            self.assertLessEqual(os.path.getsize(new), bootimg.MAX_IMAGE)
            # independent unpack of the result and of the original
            for name, path in (("new", new), ("old", BOOT_B)):
                d = os.path.join(t, "u" + name)
                os.makedirs(d)
                self.assertEqual(os.system(f"cd {d} && {MB} unpack {path} >/dev/null 2>&1"), 0)
            u = lambda n, f: bootimg.sha(os.path.join(t, "u" + n, f))
            self.assertEqual(u("new", "kernel"), bootimg.sha(image))
            self.assertEqual(u("new", "ramdisk.cpio"), u("old", "ramdisk.cpio"))

    def test_spliced_source_is_refused(self):
        # a new image written over the old boot_b (what a half-finished dd leaves behind) must never be rebuilt
        with tempfile.TemporaryDirectory() as t:
            image = os.path.join(t, "Image")
            with zipfile.ZipFile(ZIP) as z, open(image, "wb") as f:
                f.write(z.read("Image"))
            new = bootimg.build_boot(image, BOOT_B, os.path.join(t, "w"), MB)
            with open(new, "rb") as f:
                newb = f.read()
            with open(BOOT_B, "rb") as f:
                old = f.read()
            ksize = int.from_bytes(newb[8:12], "little")
            ramdisk_start = 4096 + (ksize + 4095) // 4096 * 4096
            for cut in (1 << 20, 20 << 20, ramdisk_start):
                spliced = os.path.join(t, f"splice-{cut}.img")
                with open(spliced, "wb") as f:
                    f.write(newb[:cut] + old[cut:])
                with self.subTest(cut=cut):
                    with self.assertRaises(bootimg.BootImgError) as c:
                        bootimg.build_boot(image, spliced, os.path.join(t, f"w{cut}"), MB)
