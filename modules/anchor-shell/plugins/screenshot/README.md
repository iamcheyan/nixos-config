# Anchor Shell Screenshot

Labwc screenshot selection is split between this plugin and the compatibility
scripts in `modules/labwc/labwc/scripts/`:

- `Service.qml` captures each output with `grim`, waits for all captures to
  finish, then opens a frozen selection layer for each screen.
- `FrozenSurface.qml` displays the saved frame, dims the area outside the
  selection, and sends the selected crop to `omarchy-capture-frozen`.
- `omarchy-capture-screenshot` starts the frozen selector for interactive
  modes. The helper currently saves the crop under `Pictures` and copies it to
  the clipboard.

## Current selection controls

| Input | Behavior |
|---|---|
| Drag | Select a rectangular region on one display |
| Hold Shift while dragging | Temporarily constrain the selection to a square (1:1) |
| Esc | Cancel and discard the frozen captures |
| Release pointer | Save the crop and copy it to the clipboard |

The Shift constraint is applied while the key is held and released immediately
when Shift is released. The square grows from the initial pointer position and
is clamped to the current display edges. This restores the modifier behavior
that the previous `slurp` picker provided. The local `slurp` package is 1.5.0;
its keyboard controls document Shift as a temporary 1:1 aspect-ratio lock when
no fixed aspect ratio was requested: [slurp(1)](https://man.archlinux.org/man/slurp.1).
Press Print first, then hold Shift while dragging. `Shift+Print` remains the
separate delayed-fullscreen shortcut.

## Previous Labwc shortcuts and behavior

These are the bindings in `modules/labwc/labwc/rc.xml` and the matching
`keybind-profile` template:

| Shortcut | Previous behavior |
|---|---|
| Print | Open `slurp`; save the selected region and copy it |
| Alt+Print | Save a fullscreen capture |
| Shift+Print | Wait three seconds, then capture fullscreen |
| Ctrl+Shift+Print | Save a capture of the display under the pointer |
| Super+Shift+A | Select a region and copy it only |

While the old selector was open, Esc cancelled selection, Space moved the
current rectangle, and Shift temporarily locked it to a square. The installed
`omarchy-capture-region` maps `smart`, `region`, and `windows` to plain `slurp`,
so those mode names did not provide separate smart or window-snapping behavior.

Other capture utilities remain separate scripts:

- `omarchy-capture-text`: select a region, OCR it, and copy the text.
- `omarchy-capture-qr`: select a region, decode a QR code, and copy the result.
- `omarchy-capture-screenrecording`: record a selected region or the full
  screen, with optional audio flags.
- `omarchy-delayed-screenshot`: wait before starting a region or fullscreen
  screenshot.

## Differences to consider

The frozen picker currently adds a stable captured frame, a dimmed outside
area, and selection on each output. Apart from the Shift square constraint and
Esc cancellation, it does not yet restore the old Space-to-move behavior or
the distinct shortcut output modes. All interactive modes currently use the
same frozen picker and save-plus-copy result; mode names and the requested
`copy`/`save` processing mode are not passed through to the plugin.

The following decisions are intentionally deferred:

1. Restore Space to move an already drawn selection.
2. Preserve each shortcut's save, copy, and delayed-capture behavior.
3. Add window or monitor snapping and keyboard-based window selection.

OCR, QR scanning, and screen recording already have dedicated helpers and do
not need to be folded into the screenshot selector. The above list records
possible follow-up work; it does not imply those features are implemented.
