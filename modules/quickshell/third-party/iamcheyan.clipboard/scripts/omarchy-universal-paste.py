#!/usr/bin/env python3
"""Paste the clipboard using Omarchy's terminal/non-terminal focus policy."""

from __future__ import annotations

import json
import os
import subprocess
import sys


TRUSTED_EXECUTABLE_DIRS = (
    "/usr/bin",
    "/run/current-system/sw/bin",
    "/bin",
)


def trusted_executable(name: str) -> str:
    """Resolve a system helper without consulting the ambient PATH."""
    for directory in TRUSTED_EXECUTABLE_DIRS:
        candidate = os.path.join(directory, name)
        if os.access(candidate, os.X_OK):
            return candidate
    raise RuntimeError(f"required executable not found in trusted system paths: {name}")


def hyprland_environment() -> dict[str, str]:
    environment = dict(os.environ)
    if environment.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return environment
    try:
        instances = json.loads(
            subprocess.check_output(
                [trusted_executable("hyprctl"), "instances", "-j"], text=True
            )
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
    try:
        raw = subprocess.check_output(
            [trusted_executable("hyprctl"), "activewindow", "-j"],
            text=True,
            env=hyprland_environment(),
        )
        window = json.loads(raw)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return False
    return any(tag.rstrip("*") == "terminal" for tag in window.get("tags", []))


def send_shortcut(mods: str, key: str, state: str) -> None:
    expression = (
        "hl.dsp.send_key_state({"
        f' mods = "{mods}", key = "{key}", state = "{state}"'
        " })"
    )
    subprocess.run(
        [trusted_executable("hyprctl"), "dispatch", expression],
        check=False,
        env=hyprland_environment(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> None:
    if sys.argv[1:] and sys.argv[1] != "paste":
        raise SystemExit("usage: omarchy-universal-paste.py [paste]")
    mods, key = ("SHIFT", "Insert") if active_window_is_terminal() else ("CTRL", "V")
    send_shortcut(mods, key, "down")
    send_shortcut(mods, key, "up")


if __name__ == "__main__":
    main()
