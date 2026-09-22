#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "desktop-index"
ADD_HELPER = ROOT / "bin" / "add-to-desktop"


def load_script(name, path):
    bin_dir = str(ROOT / "bin")
    if bin_dir not in sys.path:
        sys.path.insert(0, bin_dir)
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def load_helper():
    return load_script("desktop_index", HELPER)


class DesktopIndexSecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_helper()

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.desktop = Path(self._tmp.name) / "Desktop"
        self.desktop.mkdir()
        self.mod.desktop_dir = lambda: self.desktop

    def tearDown(self):
        self._tmp.cleanup()

    def write_desktop(self, name, body, executable=False):
        path = self.desktop / name
        path.write_text(body, encoding="utf-8")
        if executable:
            path.chmod(path.stat().st_mode | 0o111)
        return path

    def listed(self, filename):
        payload = self.mod.list_items()
        for item in payload["items"]:
            if item["id"] == filename:
                return item
        self.fail(f"missing desktop item {filename}")

    def test_plain_text_strips_html_and_controls(self):
        cleaned = self.mod.plain_text(
            "<img src='https://example.invalid/x.png'>\x07Firefox\n"
        )
        self.assertEqual(cleaned, "Firefox")
        self.assertNotIn("<", cleaned)
        self.assertNotIn(">", cleaned)

    def test_sanitize_icon_rejects_remote_and_odd_protocols(self):
        self.assertEqual(self.mod.sanitize_icon("https://example.invalid/x.png"), "")
        self.assertEqual(self.mod.sanitize_icon("http://127.0.0.1/x.png"), "")
        self.assertEqual(self.mod.sanitize_icon("image://plugin/x"), "")
        self.assertEqual(self.mod.sanitize_icon("qrc:/x.png"), "")
        self.assertEqual(self.mod.sanitize_icon("data:image/png;base64,aaaa"), "")
        self.assertEqual(self.mod.sanitize_icon("file://evil.example/x.png"), "")
        self.assertEqual(self.mod.sanitize_icon("//evil.example/share/x.png"), "")
        self.assertEqual(self.mod.sanitize_icon("firefox"), "firefox")
        self.assertEqual(self.mod.sanitize_icon("org.mozilla.firefox"), "org.mozilla.firefox")
        self.assertEqual(self.mod.sanitize_icon("input-keyboard+virtual"), "input-keyboard+virtual")

    def test_sanitize_icon_accepts_small_local_file(self):
        icon = self.desktop / "ok.png"
        icon.write_bytes(b"\x89PNG\r\n" + b"x" * 32)
        self.assertEqual(self.mod.sanitize_icon(str(icon)), str(icon.resolve()))
        self.assertEqual(self.mod.sanitize_icon(icon.resolve().as_uri()), str(icon.resolve()))

    def test_sanitize_icon_rejects_huge_svg_and_outside_roots(self):
        huge = self.desktop / "huge.png"
        huge.write_bytes(b"x" * (self.mod.MAX_ICON_FILE_BYTES + 1))
        self.assertEqual(self.mod.sanitize_icon(str(huge)), "")

        svg = self.desktop / "icon.svg"
        svg.write_text("<svg xmlns='http://www.w3.org/2000/svg'><image href='https://example.invalid/x'/></svg>")
        self.assertEqual(self.mod.sanitize_icon(str(svg)), "")

        outside = Path(self._tmp.name) / "outside.png"
        outside.write_bytes(b"\x89PNG\r\n" + b"x" * 32)
        self.assertEqual(self.mod.sanitize_icon(str(outside)), "")

    def test_untrusted_launcher_sanitizes_name_and_icon(self):
        self.write_desktop(
            "bait.desktop",
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=<img src=\"https://example.invalid/t.png\">Firefox\n"
            "Icon=https://example.invalid/firefox.png\n"
            "Exec=/usr/bin/true\n",
        )
        item = self.listed("bait.desktop")
        self.assertEqual(item["kind"], "launcher")
        self.assertFalse(item["trusted"])
        self.assertEqual(item["name"], "Firefox")
        self.assertEqual(item["icon"], "application-x-executable")
        self.assertNotIn("<", item["name"])
        self.assertNotIn("https://", item["icon"])

    def test_executable_bit_is_enough_to_trust(self):
        path = self.write_desktop(
            "safe.desktop",
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=<b>Calculator</b>\n"
            "Icon=https://example.invalid/calc.png\n"
            "Exec=/usr/bin/true\n",
            executable=True,
        )
        self.assertTrue(self.mod.is_trusted_desktop(path))
        item = self.listed("safe.desktop")
        self.assertTrue(item["trusted"])
        self.assertEqual(item["name"], "Calculator")
        self.assertEqual(item["icon"], "application-x-executable")

    def test_mark_trusted_sets_executable_and_metadata(self):
        path = self.write_desktop(
            "pin.desktop",
            "[Desktop Entry]\nType=Application\nName=Pin\nExec=/usr/bin/true\n",
        )
        self.assertFalse(self.mod.is_trusted_desktop(path))
        self.mod.mark_trusted(path)
        self.assertTrue(path.stat().st_mode & stat.S_IXUSR)
        self.assertTrue(self.mod.is_trusted_desktop(path))

    def test_open_untrusted_launcher_is_rejected(self):
        path = self.write_desktop(
            "evil.desktop",
            "[Desktop Entry]\nType=Application\nName=Evil\nExec=/usr/bin/true\n",
        )
        with self.assertRaises(PermissionError):
            self.mod.open_path(path)

    def test_open_trusted_link_rejects_dangerous_schemes(self):
        path = self.write_desktop(
            "js.desktop",
            "[Desktop Entry]\nType=Link\nName=JS\nURL=javascript:alert(1)\nIcon=text-html\n",
            executable=True,
        )
        with self.assertRaises(ValueError):
            self.mod.open_path(path)

        data = path.read_text(encoding="utf-8")
        path.write_text(data.replace("javascript:alert(1)", "data:text/html,hi"), encoding="utf-8")
        with self.assertRaises(ValueError):
            self.mod.open_path(path)

        path.write_text(data.replace("javascript:alert(1)", "file://evil.example/etc/passwd"), encoding="utf-8")
        with self.assertRaises(ValueError):
            self.mod.open_path(path)

    def test_allowed_url_schemes(self):
        self.assertTrue(self.mod.allowed_url("https://example.com/a"))
        self.assertTrue(self.mod.allowed_url("http://example.com"))
        self.assertTrue(self.mod.allowed_url("mailto:user@example.com"))
        self.assertTrue(self.mod.allowed_url("file:///home/henri/Documents"))
        self.assertTrue(self.mod.allowed_url("trash:///"))
        self.assertFalse(self.mod.allowed_url("javascript:alert(1)"))
        self.assertFalse(self.mod.allowed_url("ftp://example.com/x"))
        self.assertFalse(self.mod.allowed_url("smb://evil/share"))

    def test_item_and_output_ceilings(self):
        original_items = self.mod.MAX_ITEMS
        original_output = self.mod.MAX_OUTPUT_BYTES
        self.mod.MAX_ITEMS = 8
        self.mod.MAX_OUTPUT_BYTES = 900
        self.addCleanup(lambda: setattr(self.mod, "MAX_ITEMS", original_items))
        self.addCleanup(lambda: setattr(self.mod, "MAX_OUTPUT_BYTES", original_output))
        for index in range(20):
            (self.desktop / f"file-{index:02d}.txt").write_text("x" * 40, encoding="utf-8")
        payload = self.mod.list_items()
        encoded = self.mod.encode_payload(payload)
        self.assertLessEqual(len(payload["items"]), 8)
        self.assertTrue(payload.get("truncated"))
        self.assertLessEqual(len(encoded.encode("utf-8")), 900)

    def test_skips_huge_desktop_files_and_previews(self):
        huge_launcher = self.write_desktop("huge.desktop", "[Desktop Entry]\nName=Huge\n")
        huge_launcher.write_bytes(b"[Desktop Entry]\nName=Huge\n" + b"X" * (self.mod.MAX_DESKTOP_FILE_BYTES + 8))
        item = self.listed("huge.desktop")
        self.assertEqual(item["name"], "huge")

        blob = self.desktop / "photo.png"
        blob.write_bytes(b"x" * (self.mod.MAX_PREVIEW_BYTES + 1))
        preview_item = self.listed("photo.png")
        self.assertEqual(preview_item["preview"], "")
        self.assertEqual(preview_item["kind"], "image")

        svg = self.desktop / "drawing.svg"
        svg.write_text("<svg xmlns='http://www.w3.org/2000/svg'></svg>")
        svg_item = self.listed("drawing.svg")
        self.assertEqual(svg_item["preview"], "")
        self.assertEqual(svg_item["kind"], "image")

    def test_unique_dest_appends_numeric_suffix(self):
        (self.desktop / "Notes.txt").write_text("x", encoding="utf-8")
        dest = self.mod.unique_dest(self.desktop, "Notes.txt")
        self.assertEqual(dest.name, "Notes 2.txt")
        dest.write_text("y", encoding="utf-8")
        dest3 = self.mod.unique_dest(self.desktop, "Notes.txt")
        self.assertEqual(dest3.name, "Notes 3.txt")

    def test_place_does_not_auto_trust_copied_desktop_file(self):
        source_dir = Path(self._tmp.name) / "incoming"
        source_dir.mkdir()
        source = source_dir / "dropped.desktop"
        source.write_text(
            "[Desktop Entry]\nType=Application\nName=Dropped\nExec=/usr/bin/true\n",
            encoding="utf-8",
        )
        dest = self.mod.place_one(source, self.desktop, "copy")
        self.assertTrue(dest.exists())
        mode = dest.stat().st_mode
        self.assertFalse(mode & stat.S_IXUSR)
        self.assertFalse(self.mod.is_trusted_desktop(dest))

    def test_place_does_not_auto_trust_applications_substring(self):
        source_dir = Path(self._tmp.name) / "Downloads" / "applications"
        source_dir.mkdir(parents=True)
        source = source_dir / "evil.desktop"
        source.write_text(
            "[Desktop Entry]\nType=Application\nName=Evil\nExec=/usr/bin/true\n",
            encoding="utf-8",
        )
        dest = self.mod.place_one(source, self.desktop, "copy")
        self.assertTrue(dest.exists())
        self.assertFalse(dest.stat().st_mode & stat.S_IXUSR)
        self.assertFalse(self.mod.is_trusted_desktop(dest))

    def test_rename_folder(self):
        folder = self.desktop / "New Folder"
        folder.mkdir()
        dest = self.mod.rename_item(folder, "Projects")
        self.assertEqual(dest, self.desktop / "Projects")
        self.assertTrue(dest.is_dir())
        self.assertFalse(folder.exists())

    def test_rename_rejects_path_escape_and_outside_desktop(self):
        folder = self.desktop / "Keep"
        folder.mkdir()
        with self.assertRaises(ValueError):
            self.mod.rename_item(folder, "../evil")
        with self.assertRaises(ValueError):
            self.mod.rename_item(folder, "a/b")
        self.assertTrue(folder.exists())
        outside = Path(self._tmp.name) / "outside"
        outside.mkdir()
        with self.assertRaises(ValueError):
            self.mod.rename_item(outside, "nope")

    def test_rename_rejects_existing_and_trash(self):
        (self.desktop / "A").mkdir()
        (self.desktop / "B").mkdir()
        with self.assertRaises(ValueError):
            self.mod.rename_item(self.desktop / "A", "B")
        trash = self.write_desktop(
            "trash-can.desktop",
            "[Desktop Entry]\nType=Link\nName=Trash\nURL=trash:///\nIcon=user-trash\n",
        )
        with self.assertRaises(ValueError):
            self.mod.rename_item(trash, "Nope")
        self.assertTrue(trash.exists())

    def test_rename_url_keeps_suffix(self):
        path = self.desktop / "old.url"
        path.write_text("[InternetShortcut]\nURL=https://example.com\n", encoding="utf-8")
        dest = self.mod.rename_item(path, "Example")
        self.assertEqual(dest.name, "Example.url")
        self.assertFalse(path.exists())

    def test_rename_desktop_updates_visible_name(self):
        path = self.write_desktop(
            "app.desktop",
            "[Desktop Entry]\nType=Application\nName=App\nExec=/usr/bin/true\n",
        )
        dest = self.mod.rename_item(path, "My App")
        self.assertEqual(dest.name, "My App.desktop")
        item = self.listed("My App.desktop")
        self.assertEqual(item["name"], "My App")

    def test_rename_cli_writes_new_id(self):
        folder = self.desktop / "Old"
        folder.mkdir()
        original = self.mod.desktop_dir
        self.mod.desktop_dir = lambda: self.desktop
        self.addCleanup(lambda: setattr(self.mod, "desktop_dir", original))
        from io import StringIO
        from unittest.mock import patch
        with patch("sys.stdout", new=StringIO()) as out:
            code = self.mod.main(["--rename", str(folder), "--to", "New"])
        self.assertEqual(code, 0)
        self.assertTrue((self.desktop / "New").is_dir())
        self.assertIn('"id":"New"', out.getvalue().replace(" ", ""))

    def test_rename_symlink_via_cli_does_not_follow(self):
        target = Path(self._tmp.name) / "elsewhere"
        target.mkdir()
        link = self.desktop / "Link"
        os.symlink(target, link)
        from io import StringIO
        from unittest.mock import patch
        with patch("sys.stdout", new=StringIO()), patch("sys.stderr", new=StringIO()):
            code = self.mod.main(["--rename", str(link), "--to", "RenamedLink"])
        self.assertEqual(code, 0)
        dest = self.desktop / "RenamedLink"
        self.assertTrue(dest.is_symlink())
        self.assertTrue(target.exists())
        self.assertFalse(os.path.lexists(link))

    def test_rename_symlink_stays_on_desktop(self):
        target = Path(self._tmp.name) / "elsewhere"
        target.mkdir()
        marker = target / "keep.txt"
        marker.write_text("ok", encoding="utf-8")
        link = self.desktop / "Link"
        os.symlink(target, link)
        dest = self.mod.rename_item(link, "RenamedLink")
        self.assertEqual(dest.name, "RenamedLink")
        self.assertTrue(dest.is_symlink())
        self.assertFalse(link.exists())
        self.assertTrue(marker.exists())

    def test_rename_caps_suffix_length(self):
        path = self.desktop / "old.url"
        path.write_text("[InternetShortcut]\nURL=https://example.com\n", encoding="utf-8")
        dest = self.mod.rename_item(path, "x" * 300)
        self.assertTrue(dest.name.endswith(".url"))
        self.assertLessEqual(len(dest.name), self.mod.MAX_ID_LENGTH)

    def test_trash_symlink_does_not_delete_target(self):
        target = Path(self._tmp.name) / "real-folder"
        target.mkdir()
        marker = target / "keep.txt"
        marker.write_text("ok", encoding="utf-8")
        link = self.desktop / "Alias"
        os.symlink(target, link)
        try:
            self.mod.trash_one(link)
        except RuntimeError as err:
            if "not supported" in str(err).lower():
                self.skipTest(str(err))
            raise
        self.assertTrue(marker.exists())
        self.assertTrue(target.is_dir())
        self.assertFalse(os.path.lexists(link))

    def test_symlink_launcher_is_not_trusted_unless_in_applications(self):
        target = Path(self._tmp.name) / "real.desktop"
        target.write_text(
            "[Desktop Entry]\nType=Application\nName=Real\nExec=/usr/bin/true\n",
            encoding="utf-8",
        )
        target.chmod(target.stat().st_mode | 0o111)
        link = self.desktop / "link.desktop"
        os.symlink(target, link)
        self.assertFalse(self.mod.is_trusted_desktop(link))
        with self.assertRaises(PermissionError):
            self.mod.mark_trusted(link)

        apps = Path(self._tmp.name) / "applications"
        apps.mkdir()
        system = apps / "firefox.desktop"
        system.write_text(
            "[Desktop Entry]\nType=Application\nName=Firefox\nExec=/usr/bin/true\n",
            encoding="utf-8",
        )
        original_dirs = self.mod.trusted_application_dirs
        self.mod.trusted_application_dirs = lambda: [apps]
        self.addCleanup(lambda: setattr(self.mod, "trusted_application_dirs", original_dirs))
        pinned = self.desktop / "firefox.desktop"
        os.symlink(system, pinned)
        self.assertTrue(self.mod.is_trusted_desktop(pinned))


class AddToDesktopTrustTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_script("add_to_desktop", ADD_HELPER)

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.desktop = Path(self._tmp.name) / "Desktop"
        self.desktop.mkdir()
        self.mod.desktop_dir = lambda: self.desktop

    def tearDown(self):
        self._tmp.cleanup()

    def test_pinning_a_download_desktop_file_stays_untrusted(self):
        source_dir = Path(self._tmp.name) / "Downloads" / "applications"
        source_dir.mkdir(parents=True)
        source = source_dir / "evil.desktop"
        source.write_text(
            "[Desktop Entry]\nType=Application\nName=Evil\nExec=/usr/bin/true\n",
            encoding="utf-8",
        )
        dest = self.mod.add_shortcut(source, self.desktop)
        self.assertTrue(dest.exists())
        self.assertFalse(dest.stat().st_mode & stat.S_IXUSR)

    def test_pinning_from_applications_dir_is_trusted(self):
        apps = Path(self._tmp.name) / "applications"
        apps.mkdir()
        source = apps / "firefox.desktop"
        source.write_text(
            "[Desktop Entry]\nType=Application\nName=Firefox\nExec=/usr/bin/true\n",
            encoding="utf-8",
        )
        original = self.mod.is_trusted_application_source
        self.mod.is_trusted_application_source = lambda path: path.resolve() == source.resolve()
        self.addCleanup(lambda: setattr(self.mod, "is_trusted_application_source", original))
        dest = self.mod.add_shortcut(source, self.desktop)
        self.assertTrue(dest.stat().st_mode & stat.S_IXUSR)


class QmlSecurityTests(unittest.TestCase):
    def test_all_text_elements_force_plain_text(self):
        import re

        source = (ROOT / "Service.qml").read_text(encoding="utf-8")
        text_elements = len(re.findall(r"(?m)^\s*Text\s*\{", source))
        plain_text = len(re.findall(r"(?m)^\s*textFormat:\s*Text\.PlainText\s*$", source))
        self.assertGreater(text_elements, 0)
        self.assertEqual(plain_text, text_elements)

    def test_image_source_uses_safe_helper(self):
        source = (ROOT / "Service.qml").read_text(encoding="utf-8")
        self.assertIn("source: panel.host.iconSource(iconRoot.modelData)", source)
        self.assertIn("function safeIconSource(", source)
        self.assertIn("function isBlockedIconUrl(", source)
        self.assertIn("function isLocalFileUrl(", source)
        self.assertIn("textFormat: Text.PlainText", source)
        self.assertIn("--trust-and-open", source)
        self.assertIn("--rename", source)
        self.assertIn('action: "rename"', source)
        self.assertIn("bin/create-hyperlink", source)


if __name__ == "__main__":
    unittest.main()
