#!/usr/bin/env python3
import sys
from pathlib import Path
import tarfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_reference as installer


class ArchiveBoundaryTests(unittest.TestCase):
    def test_relative_sdk_links_resolve_with_correct_archive_base(self):
        symlink = tarfile.TarInfo("sdk/bin/compiler")
        symlink.type = tarfile.SYMTYPE
        symlink.linkname = "../lib/compiler"
        installer.validate_tar_member(symlink, "sdk")
        hardlink = tarfile.TarInfo("sdk/bin/compiler")
        hardlink.type = tarfile.LNKTYPE
        hardlink.linkname = "sdk/lib/compiler"
        installer.validate_tar_member(hardlink, "sdk")
        for target in ("../../outside", "/outside"):
            symlink.linkname = target
            with self.assertRaises(ValueError):
                installer.validate_tar_member(symlink, "sdk")

    def test_entry_paths_and_special_files_stay_inside_the_sdk(self):
        for path in ("/sdk/file", "sdk/../outside", "other/file"):
            with self.assertRaises(ValueError):
                installer.safe_member(path, "sdk")
        special = tarfile.TarInfo("sdk/device")
        special.type = tarfile.CHRTYPE
        with self.assertRaises(ValueError):
            installer.validate_tar_member(special, "sdk")


if __name__ == "__main__":
    unittest.main()
