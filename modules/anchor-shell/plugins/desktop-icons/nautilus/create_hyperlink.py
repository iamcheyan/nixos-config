import os
import shutil

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, Nautilus


class CreateHyperlinkAction(GObject.GObject, Nautilus.MenuProvider):
    def _script(self):
        candidates = [
            shutil.which("create-hyperlink"),
            os.path.expanduser(
                "~/.config/omarchy/plugins/henri.desktop-icons/bin/create-hyperlink"
            ),
            os.path.expanduser("~/.local/bin/create-hyperlink"),
        ]
        for path in candidates:
            if path and os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        return None

    def _writable_dir(self, file):
        if not file:
            return None
        location = file.get_location()
        if not location:
            return None
        path = location.get_path()
        if path and os.path.isdir(path) and os.access(path, os.W_OK):
            return path
        return None

    def _selected_paths(self, files):
        paths = []
        for file in files:
            location = file.get_location()
            if not location:
                continue
            path = location.get_path()
            if not path:
                continue
            name = file.get_name() or ""
            mime = file.get_mime_type() or ""
            if mime == "application/x-mswinurl" or name.lower().endswith(".url"):
                continue
            if path not in paths:
                paths.append(path)
        return paths

    def _launch(self, command):
        script = self._script()
        if not script or not os.path.exists(script):
            return
        Gio.Subprocess.new([script, *command], Gio.SubprocessFlags.NONE)

    def get_background_items(self, *args):
        folder = args[-1]
        directory = self._writable_dir(folder)
        if not directory:
            return []

        item = Nautilus.MenuItem(
            name="CreateHyperlinkNautilus::create_hyperlink_here",
            label="Create Hyperlink…",
            icon="insert-link",
        )
        item.connect("activate", lambda *_: self._launch(["--directory", directory]))
        return [item]

    def get_file_items(self, *args):
        files = args[-1]
        paths = self._selected_paths(files)
        if not paths:
            return []

        writable = False
        for path in paths:
            parent = os.path.dirname(path)
            if os.access(parent, os.W_OK):
                writable = True
                break
        if not writable:
            return []

        if len(paths) == 1:
            label = "Create Hyperlink"
        else:
            label = f"Create Hyperlink to {len(paths)} items"

        item = Nautilus.MenuItem(
            name="CreateHyperlinkNautilus::create_hyperlink_to",
            label=label,
            icon="insert-link",
        )
        item.connect("activate", lambda *_: self._launch(["--link", *paths]))
        return [item]
