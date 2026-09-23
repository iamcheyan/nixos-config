#!/usr/bin/env python3
"""Helpers shared by the desktop-icons plugin scripts (desktop-index, add-to-desktop)."""

from __future__ import annotations

import os
import re
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

MAX_FOLDER_METADATA_BYTES = 64 * 1024
THEME_ICON_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")


def desktop_dir() -> Path:
    special = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP)
    path = Path(special) if special else Path.home() / "Desktop"
    if path.resolve() == Path.home().resolve():
        path = Path.home() / "Desktop"
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def unique_dest(directory: Path, name: str) -> Path:
    candidate = directory / name
    if not candidate.exists():
        return candidate
    stem = Path(name).stem
    suffix = Path(name).suffix
    if name.endswith(suffix) and suffix:
        base = name[: -len(suffix)]
    else:
        base = name
        suffix = ""
    index = 2
    while True:
        candidate = directory / f"{base} {index}{suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def guess_icon(path: Path) -> str:
    if path.is_dir():
        return "folder"
    content_type, _uncertain = Gio.content_type_guess(str(path), None)
    icon = Gio.content_type_get_generic_icon_name(content_type) if content_type else None
    return icon or "text-x-generic"


def folder_custom_icon(path: Path) -> str:
    """Read a folder's saved theme icon for snapshotting into a new shortcut."""
    if not path.is_dir():
        return ""
    metadata = path / ".directory"
    try:
        if metadata.is_symlink() or not metadata.is_file():
            return ""
        if metadata.stat().st_size > MAX_FOLDER_METADATA_BYTES:
            return ""
        keyfile = GLib.KeyFile()
        keyfile.load_from_file(str(metadata), GLib.KeyFileFlags.NONE)
        icon = keyfile.get_string("Desktop Entry", "Icon").strip()
    except (GLib.Error, OSError):
        return ""
    return icon if THEME_ICON_RE.fullmatch(icon) else ""


def is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except (ValueError, OSError):
        return False


def trusted_application_dirs() -> list[Path]:
    dirs: list[Path] = []
    seen: set[str] = set()

    def add(path: Path) -> None:
        try:
            resolved = path.expanduser().resolve()
        except OSError:
            return
        key = str(resolved)
        if key in seen:
            return
        seen.add(key)
        dirs.append(resolved)

    add(Path("/usr/share/applications"))
    add(Path("/usr/local/share/applications"))
    add(Path.home() / ".local/share/applications")
    for raw in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if raw.strip():
            add(Path(raw) / "applications")
    data_home = os.environ.get("XDG_DATA_HOME")
    if data_home:
        add(Path(data_home) / "applications")
    return dirs


def is_trusted_application_source(path: Path) -> bool:
    try:
        resolved = path.expanduser().resolve()
    except OSError:
        return False
    return any(is_under(resolved, directory) for directory in trusted_application_dirs())
