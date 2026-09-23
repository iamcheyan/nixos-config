# Desktop Icons

Windows-style files and shortcuts on the Omarchy wallpaper.

## Anchor Shell migration note

This copy is managed by Anchor Shell in `modules/anchor-shell/plugins/desktop-icons/`.
It keeps the local plugin ID and command behavior, but stores icon positions
under `~/.local/state/anchor-shell/`. The icon layer owns the whole output so
marquee selection can start from any edge. Empty-wallpaper right-clicks are
forwarded to Labwc's root menu (`A-space` / `wtype`); right-clicking an icon
still opens this plugin's item menu.

Labwc 上出现过的空白图标、框选方向、跨屏拖拽问题，以及不能改回去的约束，记在
[docs/runtime-troubleshooting.md](docs/runtime-troubleshooting.md)。

## Upstream source and local maintenance

- Upstream repository: [Henri1130/omarchy-desktop-icons](https://github.com/Henri1130/omarchy-desktop-icons)
- Upstream plugin directory: repository root, originally published as `desktop-icons`
- Local maintained copy: `modules/anchor-shell/plugins/desktop-icons/`

This copy includes Anchor Shell/Labwc integration and local multi-monitor behavior.
Review upstream changes manually before applying them here; the active copy is not
updated with `omarchy plugin update`.

> [!IMPORTANT]
> This plugin is for **Omarchy 4 (Quattro)**, where the desktop shell uses
> [Quickshell](https://quickshell.org/).

## What it does

- Shows `~/Desktop` as icons on every monitor, under windows and the bar
- Snapshots a folder's Dolphin color icon into a new desktop shortcut; later color changes do not alter the shortcut
- Double-click an icon to open it; single-click selects it, and dragging moves it (snaps to a grid)
- Drag on empty wallpaper to draw a selection rectangle; intersecting icons are selected together
- On multiple monitors, each icon belongs to one monitor and can be dragged across the virtual desktop; its monitor assignment and grid position are remembered
- Right-click empty wallpaper opens Labwc's native desktop menu (the layer forwards `A-space`); right-clicking an icon opens this plugin's item menu
- Right-click an icon: Open, Rename, Show in Files, Move to Trash
- Drag an icon onto Trash, or drop files from Files onto Trash, to delete them
- Drag files from Files onto the wallpaper to copy them there
- Untrusted `.desktop` launchers show a warning badge and ask before they run

`.desktop` launchers only run if they are trusted: they came from a real Applications directory (`/usr/share/applications`, `~/.local/share/applications`, and other XDG application dirs), the file is marked executable, or you allow launching from the desktop (same model as GNOME). A folder merely named `applications` is not enough. Names and icons from launchers are treated as plain text and local theme or raster image files only. Remote URLs, inline resources, SVG/GIF icon loading, and unbounded Desktop folders are rejected.

## Install

Point Omarchy at a real `~/Desktop` folder first, if you do not already have one:

```bash
mkdir -p ~/Desktop
```

In `~/.config/user-dirs.dirs` set:

```bash
XDG_DESKTOP_DIR="$HOME/Desktop"
```

Then:

```bash
xdg-user-dirs-update
```

The active Anchor Shell copy is loaded from the Nix-managed repository path above.
The upstream `omarchy plugin add` command is only for installing the standalone
Omarchy version and is not part of the Anchor Shell runtime.

### Dolphin context menu

The Anchor Shell NixOS integration installs a Dolphin service menu named
**Send to Desktop (create shortcut)**. It accepts files, folders, and application
launchers selected in Dolphin and reuses `bin/add-to-desktop`.

## Use

| Action | How |
| --- | --- |
| Open | Double-click an icon (untrusted launchers ask first) |
| Select / keyboard | Drag on empty wallpaper to marquee-select; `Tab` / arrows move the selection; `Enter` opens, `F2` renames one item, `Delete` trashes selected items, `Esc` cancels |
| Rename | Right-click an icon → Rename, or select it and press `F2` |
| Allow a launcher | Click **Trust and Open**, or right-click **Allow launching** |
| Move an icon | Drag it; it snaps to the grid and can cross to another monitor |
| Put a file on the desktop | Drag it onto the wallpaper, or copy it into `~/Desktop` |
| Pin a shortcut | Dolphin → right-click → **Send to Desktop (create shortcut)** |
| Trash | Right-click an icon → Move to Trash, press Delete, or drag onto Trash |
| Change wallpaper | `Super+Ctrl+Space` |

**Pin application** from Applications marks launchers as trusted. **Send to Desktop** and copies of a `.desktop` file only auto-trust when the source is under a real Applications directory. A `.desktop` file that merely appears in `~/Desktop` without the executable bit does not.

## Validate from source

```bash
omarchy plugin validate .
python3 tests/test_desktop_index.py
```

## Improvements

These changes keep the plugin's security model intact (remote/SVG icons
rejected, trust required, sizes bounded, no shell-out of Exec) while
improving responsiveness, ordering, and accessibility:

- **Instant refresh:** the Desktop folder is watched via a `FileView`
  (`watchChanges`), so icons appear, move, or get deleted instantly when the
  watch fires. A short debounce coalesces bursty events, and a 30 s safety poll
  backs it up when the watch misses. A running-process guard prevents overlap.
- **Keyboard navigation:** `Tab` / `Shift+Tab` / arrow keys move the
  selection in visual grid order (top-to-bottom, left-to-right); `Enter`
  opens, `Delete` trashes, `Esc` cancels.
- **New items at the bottom, no overlap:** added shortcuts or folders are
  placed in the bottom-most free grid cell (just past the last icon),
  skipping any cell already occupied by a manually dragged icon. Existing
  icons keep their positions, and dragging an icon is never disturbed.
- **Trust prompt by the icon:** the "Untrusted launcher" dialog now opens
  next to the icon instead of screen-centered.
- **Cleaner code:** `desktop_dir()`, `guess_icon()`, and `unique_dest()`
  were extracted into `bin/common.py` and imported by both `desktop-index`
  and `add-to-desktop`.
- **Correct paths:** `place_one` returns the real created path (capturing
  the helper's stdout), and `add-to-desktop` prints the created path.
- **Trust from real Applications dirs only:** pinning or copying a
  `.desktop` file no longer auto-trusts just because a parent folder is
  named `applications` (for example `~/Downloads/applications`).
- **Rename:** right-click **Rename** or press `F2` to rename folders,
  files, and shortcuts in place. The icon stays on its grid cell.
- **New Shortcut:** the hyperlink dialog ships in `bin/create-hyperlink`,
  so published installs can paste a web address without a separate
  `~/.local/bin` copy.
