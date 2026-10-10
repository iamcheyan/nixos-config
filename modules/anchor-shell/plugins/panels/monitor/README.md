# Display panel

The `omarchy.monitor` first-party panel manages display arrangement and
per-output settings in Anchor Shell. Its layout preview supports dragging
outputs. The Display tab contains arrangement, resolution, and scale. The
Appearance tab contains brightness, night light, text size, refresh rate,
rotation, and connected-display controls when they apply.

This panel is maintained in this repository and carries the Omarchy runtime
ID for compatibility. Its upstream source and MIT license are recorded in
[`UPSTREAM.md`](UPSTREAM.md) and [`LICENSE`](LICENSE). The current Labwc implementation uses the local
`omarchy-display-randr` compatibility command, backed by `wlr-randr`; the
brightness controls use `omarchy-brightness-display`. The shared display
command also retains a Hyprland path. Night light is owned by the
`omarchy.nightlight` service and is controlled through
`omarchy-display-nightlight` (wlsunset on Labwc).

Relevant source and behavior:

- [`Panel.qml`](Panel.qml): panel UI, keyboard navigation, and settings
- [`MonitorArrangement.qml`](MonitorArrangement.qml): draggable display map
- [`Model.js`](Model.js): mode, scale, and temperature helpers
- [`../../services/nightlight/Service.qml`](../../services/nightlight/Service.qml):
  shared night-light state
- [`../../../compat/omarchy/bin/omarchy-display-randr`](../../../compat/omarchy/bin/omarchy-display-randr):
  output control and persistence
- [`../../../compat/omarchy/bin/omarchy-display-nightlight`](../../../compat/omarchy/bin/omarchy-display-nightlight):
  night-light control

The night-light service and display commands are global/shared system
integrations, not a separately vendored third-party panel. No upstream panel README exists; this file documents the local behavior. Keep
the Omarchy runtime ID stable unless all shell layouts and IPC callers are
migrated with it.
