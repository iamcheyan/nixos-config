# Screen recording

First-party overlay that records the Labwc session with `gpu-screen-recorder`.

The top-bar indicator is `plugins/bar/indicators/ScreenRecording.qml`.

- Left click: dim the desktop, drag a bright region, wait through a 3-2-1
  countdown, then record. A timer bar with pause and stop sits outside the
  captured region.
- Right click: open recording and capture actions. Capture a free area to open
  the screenshot selector, or capture the entire display under the indicator
  directly to the clipboard.
- Esc cancels selection and countdown. Pause and stop are on the live bar.
- Files save to Videos.

Pause sends `SIGUSR2` to `gpu-screen-recorder`. Stop sends `SIGINT` so the
MP4 trailer is written.
