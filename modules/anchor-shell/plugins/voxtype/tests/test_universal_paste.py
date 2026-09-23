from __future__ import annotations

import importlib.util
import os
import stat
import subprocess
import tempfile
import unittest
import warnings
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "scripts" / "omarchy-universal-paste.py"
SPEC = importlib.util.spec_from_file_location("omarchy_universal_paste", SCRIPT)
assert SPEC and SPEC.loader
universal_paste = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(universal_paste)


def fake_wl_paste(directory: Path, payload: str) -> None:
    script = directory / "wl-paste"
    script.write_text(f"#!/bin/sh\nprintf '%s' '{payload}'\n")
    script.chmod(0o755)


class UniversalPasteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.runtime = Path(self.temp_dir.name) / "runtime"
        self.runtime.mkdir()
        patcher = mock.patch.dict(
            os.environ, {"XDG_RUNTIME_DIR": str(self.runtime)}, clear=False
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_missing_xdg_runtime_dir_refuses_shared_location(self) -> None:
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": ""}, clear=False):
            with self.assertRaisesRegex(RuntimeError, "XDG_RUNTIME_DIR"):
                universal_paste.state_marker_path()

    def test_state_directory_is_private_and_owned(self) -> None:
        marker = universal_paste.state_marker_path()
        info = marker.parent.lstat()
        self.assertEqual(info.st_uid, os.geteuid())
        self.assertTrue(stat.S_ISDIR(info.st_mode))
        self.assertEqual(info.st_mode & 0o777, 0o700)

    def test_snapshot_roundtrip_detects_change(self) -> None:
        bindir = Path(self.temp_dir.name) / "bin"
        bindir.mkdir()
        fake_wl_paste(bindir, "first take")
        with mock.patch.dict(os.environ, {"PATH": f"{bindir}:{os.environ['PATH']}"}):
            universal_paste.snapshot_clipboard()
            # Same clipboard content must not count as new speech output.
            self.assertFalse(universal_paste.clipboard_changed())
            # Snapshot BEFORE switching content: changed() compares current
            # clipboard against the snapshot taken at dictation start.
            universal_paste.snapshot_clipboard()
            fake_wl_paste(bindir, "second take")
            self.assertTrue(universal_paste.clipboard_changed())

    def test_changed_without_marker_is_false(self) -> None:
        bindir = Path(self.temp_dir.name) / "bin"
        bindir.mkdir()
        fake_wl_paste(bindir, "anything")
        with mock.patch.dict(os.environ, {"PATH": f"{bindir}:{os.environ['PATH']}"}):
            self.assertFalse(universal_paste.clipboard_changed())

    def test_symlinked_marker_is_rejected(self) -> None:
        marker = universal_paste.state_marker_path()
        outside = Path(self.temp_dir.name) / "outside.txt"
        outside.write_text("none")
        marker.symlink_to(outside)
        self.assertIsNone(universal_paste.read_marker(marker))

    def test_marker_written_owner_only(self) -> None:
        marker = universal_paste.state_marker_path()
        universal_paste.write_marker(marker, "abc")
        info = marker.lstat()
        self.assertTrue(stat.S_ISREG(info.st_mode))
        self.assertEqual(info.st_mode & 0o777, 0o600)

    def test_oversized_clipboard_is_truncated_instead_of_buffered(self) -> None:
        bindir = Path(self.temp_dir.name) / "bin"
        bindir.mkdir()
        big = "x" * (2 * 1024 * 1024)
        script = bindir / "wl-paste"
        script.write_text(f"#!/bin/sh\nprintf '%s' '{big}'\n")
        script.chmod(0o755)
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always", ResourceWarning)
            with mock.patch.dict(os.environ, {"PATH": f"{bindir}:{os.environ['PATH']}"}):
                with mock.patch.object(
                    universal_paste, "MAX_CLIPBOARD_BYTES", 1024 * 1024
                ):
                    digest = universal_paste.clipboard_digest()
        self.assertIsNotNone(digest)
        assert digest is not None
        self.assertTrue(digest.startswith("truncated:"), digest[:32])
        self.assertFalse(
            any(item.category is ResourceWarning for item in caught),
            caught,
        )
        # The producer must have been killed rather than streamed to completion.
        self.assertLess(len(big), 4 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
