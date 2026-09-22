import os
import shutil

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GLib, GObject, Gio, Nautilus


class AddToDesktopAction(GObject.GObject, Nautilus.MenuProvider):
    def _script(self):
        candidates = [
            shutil.which("add-to-desktop"),
            os.path.expanduser(
                "~/.config/omarchy/plugins/henri.desktop-icons/bin/add-to-desktop"
            ),
            os.path.expanduser("~/.local/bin/add-to-desktop"),
        ]
        for path in candidates:
            if path and os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        return None

    def _desktop_dir(self):
        special = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DESKTOP)
        path = special or os.path.expanduser("~/Desktop")
        home = os.path.realpath(os.path.expanduser("~"))
        real = os.path.realpath(path)
        if real == home:
            real = os.path.join(home, "Desktop")
        return real

    def _selected_paths(self, files):
        desktop = self._desktop_dir()
        paths = []
        for file in files:
            location = file.get_location()
            if not location:
                continue
            path = location.get_path()
            if not path:
                continue
            real = os.path.realpath(path)
            if real == desktop or os.path.dirname(real) == desktop:
                continue
            if path not in paths:
                paths.append(path)
        return paths

    def _launch(self, extra_args, paths):
        script = self._script()
        if not script or not os.path.exists(script):
            return
        Gio.Subprocess.new([script, *extra_args, *paths], Gio.SubprocessFlags.NONE)

    def get_file_items(self, *args):
        files = args[-1]
        paths = self._selected_paths(files)
        if not paths:
            return []

        if len(paths) == 1:
            shortcut_label = "Send to Desktop (create shortcut)"
            copy_label = "Copy to Desktop"
        else:
            shortcut_label = f"Send {len(paths)} shortcuts to Desktop"
            copy_label = f"Copy {len(paths)} items to Desktop"

        shortcut = Nautilus.MenuItem(
            name="AddToDesktopNautilus::send_to_desktop",
            label=shortcut_label,
            icon="user-desktop",
        )
        shortcut.connect("activate", lambda *_: self._launch([], paths))

        copy = Nautilus.MenuItem(
            name="AddToDesktopNautilus::copy_to_desktop",
            label=copy_label,
            icon="folder-copy",
        )
        copy.connect("activate", lambda *_: self._launch(["--copy"], paths))
        return [shortcut, copy]
