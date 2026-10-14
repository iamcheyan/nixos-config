# OmaDock for Labwc / Anchor Shell

Labwc application dock for Anchor Shell. Window state comes from Quickshell's
Wayland `ToplevelManager` (`wlr-foreign-toplevel-management`). Live hover
thumbnails use Quickshell `ScreencopyView` with labwc-plus
`hyprland-toplevel-export`. There is no Hyprland IPC and no
`Quickshell.Hyprland` import.

## Features

- **Per-output dock**: One surface on each connected display. Running windows
  are attributed to the output they currently occupy (and the active workspace
  via Labwc's foreign-toplevel output membership).
- **Compact static icons**: 22px icons, 2px gap, 40px exclusive zone. No
  magnification animation and no outer stroke on the pill.
- **Pinned applications**:
  - Persistent list in `~/.config/anchor-shell/dock.json`.
  - Right-click to pin or unpin.
  - Separator between pinned apps and unpinned running apps.
- **Drag to rearrange**: Any visible icon can be dragged, pinned or running.
  Dropping a running app into the dock body pins it at that slot. Trailing
  unpinned apps stay unpinned when you only reorder existing pins.
- **Running indicators**: Left-edge pill; taller when the app is focused.
  Multi-window count badge on the icon.
- **Window list popup**: Title cards with Active / Minimized states, plus close.
  Live thumbnails stay aligned with the hovered icon, scale proportionally to
  fit every open window on screen, and never require scrolling.
- **Context menu**: New Window, Pin to Dock / Remove from Dock, Close All Windows.
- **Appearance settings**: Right-click an icon and open Dock Settings to adjust
  icon size, icon slot size, spacing, dock width, vertical padding, pill and
  hover radii, and linked Dock / top bar opacity. Settings are saved beside the pin list
  in `~/.config/anchor-shell/dock.json`, with the linked opacity also written to
  `shell.json`; Reset to Defaults returns the appearance values
  to their defaults without changing pinned applications.

## Performance

The per-output app list is rebuilt only when identity or fields change.
Repeater delegates are keyed by count so focus changes rebind properties
instead of recreating icon `Image` items. Desktop-entry name/icon lookups
are cached on the shared `Dock.qml` host. Toplevel storms (workspace
switches) are coalesced to one refresh per frame.
