#!/usr/bin/env python3
"""Paste Voxtype's already-populated clipboard using Omarchy's focus rules."""

from __future__ import annotations

import json
import hashlib
import os
import pathlib
import shutil
import subprocess
import stat
import sys
import time

MAX_CLIPBOARD_BYTES = 8 * 1024 * 1024
CHUNK_BYTES = 64 * 1024


def state_marker_path() -> pathlib.Path:
    """Marker path inside a private per-user runtime directory.

    The /tmp fallback is intentionally gone: a predictable shared directory
    would let any local user pre-place or swap the marker file.
    """
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        raise RuntimeError(
            "XDG_RUNTIME_DIR is not set; refusing to store clipboard state "
            "in a world-readable location"
        )
    directory = pathlib.Path(runtime_dir) / "voxtype-enhance"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if info.st_uid != os.geteuid() or not stat.S_ISDIR(info.st_mode):
        raise RuntimeError("voxtype-enhance state directory is not a private directory")
    os.chmod(directory, 0o700)
    return directory / "clipboard-before.sha256"


def write_marker(path: pathlib.Path, marker: str) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="ascii") as handle:
        handle.write(marker)


def read_marker(path: pathlib.Path) -> str | None:
    """Read the marker only when it is a regular file owned by this user."""
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return None
    with os.fdopen(descriptor, "r", encoding="ascii") as handle:
        info = os.fstat(handle.fileno())
        if info.st_uid != os.geteuid() or not stat.S_ISREG(info.st_mode):
            return None
        return handle.read(128).strip()


def clipboard_digest() -> str | None:
    """Hash clipboard text by streaming it in bounded chunks.

    Never holds more than one chunk in memory, and stops reading at
    MAX_CLIPBOARD_BYTES so a hostile endless source cannot pin the shell;
    the digest is flagged as truncated instead.
    """
    try:
        process = subprocess.Popen(
            ["wl-paste", "--no-newline", "--type", "text/plain"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return None
    hasher = hashlib.sha256()
    total = 0
    truncated = False
    stream = process.stdout
    try:
        while stream is not None:
            chunk = stream.read(CHUNK_BYTES)
            if not chunk:
                break
            hasher.update(chunk)
            total += len(chunk)
            if total >= MAX_CLIPBOARD_BYTES:
                truncated = True
                break
    finally:
        if truncated:
            process.kill()
        if stream is not None:
            stream.close()
        process.wait()
    if total == 0 or (process.returncode != 0 and not truncated):
        return None
    digest = hasher.hexdigest()
    return f"truncated:{digest}" if truncated else digest


def snapshot_clipboard() -> None:
    marker_path = state_marker_path()
    digest = clipboard_digest()
    write_marker(marker_path, "none" if digest is None else digest)


def clipboard_changed() -> bool:
    marker_path = state_marker_path()
    before = read_marker(marker_path)
    if not before:
        return False
    digest = clipboard_digest()
    try:
        marker_path.unlink()
    except FileNotFoundError:
        pass
    return digest is not None and before != digest


def hyprland_environment() -> dict[str, str]:
    environment = dict(os.environ)
    if environment.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return environment
    try:
        instances = json.loads(
            subprocess.check_output(["hyprctl", "instances", "-j"], text=True)
        )
        wanted_display = environment.get("WAYLAND_DISPLAY", "")
        selected = next(
            (item for item in instances if item.get("wl_socket") == wanted_display),
            instances[0] if instances else None,
        )
        if selected and selected.get("instance"):
            environment["HYPRLAND_INSTANCE_SIGNATURE"] = selected["instance"]
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, IndexError):
        pass
    return environment


def active_window_is_terminal() -> bool:
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        environment = hyprland_environment()
        try:
            raw = subprocess.check_output(
                ["hyprctl", "activewindow", "-j"], text=True, env=environment
            )
            window = json.loads(raw)
        except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
            return False
        return any(tag.rstrip("*") == "terminal" for tag in window.get("tags", []))

    # Labwc/Sway and other wlroots compositors do not expose the Hyprland IPC
    # endpoint. Ask the local Quickshell host, which reads ToplevelManager and
    # therefore uses the compositor-neutral foreign-toplevel protocol.
    try:
        quickshell_root = os.environ.get("QUICKSHELL_ROOT", "")
        command = ["qs", "ipc"]
        if quickshell_root:
            command.extend(["-p", quickshell_root])
        command.extend(["call", "shell", "activeAppId"])
        app_id = subprocess.check_output(
            command,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip().lower()
    except (OSError, subprocess.CalledProcessError):
        return False

    terminal_names = (
        "foot", "footclient", "kitty", "org.wezfurlong.wezterm", "wezterm",
        "alacritty", "ghostty", "com.mitchellh.ghostty", "konsole",
        "org.kde.konsole", "gnome-terminal", "org.gnome.console",
        "org.gnome.terminal", "xfce4-terminal", "urxvt", "xterm", "st",
    )
    return any(name.strip() == app_id or name.strip() in app_id for name in terminal_names)


def paste_to_focused_kitty() -> bool:
    """Send voice text directly to a focused Kitty window when available.

    Kitty's Ctrl+V/Shift+Insert bindings intentionally have smart image
    handling.  Reusing them for voice text can therefore try to paste an
    image from the clipboard.  Kitty remote control bypasses that ambiguity
    and preserves bracketed-paste semantics for tmux/TUIs.
    """
    try:
        payload = subprocess.check_output(
            ["wl-paste", "--no-newline", "--type", "text/plain"],
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return False
    if not payload:
        return False

    sockets = sorted(pathlib.Path("/tmp").glob("mykitty-*"))
    for socket in sockets:
        if not socket.exists():
            continue
        destination = f"unix:{socket}"
        try:
            listing = subprocess.check_output(
                ["kitty", "@", "--to", destination, "ls"],
                text=True,
                stderr=subprocess.DEVNULL,
            )
            windows = json.loads(listing)
        except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
            continue

        if not any(
            isinstance(item, dict) and item.get("is_focused")
            for item in _walk_dicts(windows)
        ):
            continue

        subprocess.run(
            [
                "kitty", "@", "--to", destination, "send-text",
                "--match", "state:focused", "--stdin",
                "--bracketed-paste", "auto",
            ],
            input=payload,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    return False


def active_app_id() -> str:
    """Read the active app id from the running Quickshell instance."""
    try:
        listing = subprocess.check_output(
            ["quickshell", "list", "--all"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        pid = next(
            (
                line.split(":", 1)[1].strip()
                for line in listing.splitlines()
                if line.strip().startswith("Process ID:")
            ),
            "",
        )
        if not pid.isdigit():
            return ""
        return subprocess.check_output(
            ["quickshell", "ipc", "--pid", pid, "call", "shell", "activeAppId"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip().lower()
    except (OSError, subprocess.CalledProcessError):
        return ""


def paste_to_focused_xwayland_app() -> bool:
    """Bridge the Wayland clipboard and send Ctrl+V through XTEST."""
    xdotool = shutil.which("xdotool")
    xclip = shutil.which("xclip")
    app_id = active_app_id()
    if not xdotool or not xclip or not app_id:
        return False

    try:
        classes = subprocess.check_output(
            [xdotool, "getwindowfocus", "getwindowclassname"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).splitlines()
    except (OSError, subprocess.CalledProcessError):
        return False

    if not any(
        app_id == window_class.strip().lower()
        or app_id in window_class.strip().lower()
        or window_class.strip().lower() in app_id
        for window_class in classes
        if window_class.strip()
    ):
        return False

    try:
        payload = subprocess.check_output(
            ["wl-paste", "--no-newline", "--type", "text/plain"],
            stderr=subprocess.DEVNULL,
        )
        if not payload:
            return False
        subprocess.run(
            [xclip, "-selection", "clipboard", "-in"],
            input=payload,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(0.05)
        subprocess.run(
            [xdotool, "key", "--clearmodifiers", "ctrl+v"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return False
    return True


def _walk_dicts(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk_dicts(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_dicts(child)


def send_shortcut(mods: str, key: str, state: str) -> None:
    # Hyprland can inject a key state through hyprctl.  Labwc has no hyprctl,
    # so use the compositor-neutral Wayland virtual-keyboard client instead.
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        if state == "down":
            subprocess.run(
                ["wtype", "-M", mods.lower(), "-k", key],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        return
    expression = (
        "hl.dsp.send_key_state({"
        f' mods = "{mods}", key = "{key}", state = "{state}"'
        " })"
    )
    subprocess.run(
        ["hyprctl", "dispatch", expression],
        check=False,
        env=hyprland_environment(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def shared_universal_clipboard() -> pathlib.Path | None:
    """Find the repository-owned universal clipboard entry point."""
    candidates = []
    configured = os.environ.get("OMARCHY_UNIVERSAL_CLIPBOARD", "")
    if configured:
        candidates.append(pathlib.Path(configured))
    candidates.append(pathlib.Path.home() / ".config/labwc/scripts/universal-clipboard")
    installed = shutil.which("omarchy-universal-clipboard")
    if installed:
        candidates.append(pathlib.Path(installed))
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def paste_via_shared_universal_clipboard() -> bool:
    """Use the same focus-aware policy as the Cmd/Ctrl+V shortcut."""
    helper = shared_universal_clipboard()
    if helper is None:
        return False
    try:
        result = subprocess.run(
            [str(helper), "paste"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return False
    return result.returncode == 0


def main() -> None:
    action = sys.argv[1] if len(sys.argv) > 1 else "paste"
    if action == "snapshot":
        snapshot_clipboard()
        return
    if action != "paste" or not clipboard_changed():
        return
    if paste_to_focused_kitty():
        return
    if paste_to_focused_xwayland_app():
        return
    if paste_via_shared_universal_clipboard():
        return
    mods, key = ("SHIFT", "Insert") if active_window_is_terminal() else ("CTRL", "V")
    send_shortcut(mods, key, "down")
    time.sleep(0.05)
    send_shortcut(mods, key, "up")


if __name__ == "__main__":
    main()
