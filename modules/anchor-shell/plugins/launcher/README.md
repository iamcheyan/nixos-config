# Launcher

`launcher` is the application launcher used by the left side of the Anchor
Shell top bar.

It intentionally contains only the application list:

- reads applications from Anchor Shell's `AppLibrary`;
- removes duplicate entries with the same visible name, icon, and command;
- provides fuzzy-free text filtering through the search field;
- displays application icons and descriptions;
- launches the selected desktop entry.
- shows the clipboard-style `⇲` action on the right when a row is hovered or
  selected, creating a trusted shortcut for that application on `~/Desktop`.

Omarchy menu actions, categories, running-application markers, pinned items,
layout settings, and menu configuration files are not part of this plugin.

## Files

- `Menu.qml` — application discovery, deduplication, filtering, and grid UI;
- `BarWidget.qml` — the `Applications` top-bar button;
- `manifest.json` — plugin metadata and entry points.

The plugin is loaded from `modules/anchor-shell/plugins/launcher/` and is
enabled in `~/.config/anchor-shell/shell.json` with the `launcher` ID.
