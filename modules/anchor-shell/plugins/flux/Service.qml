import QtQuick
import Quickshell
import qs.Commons

// The upstream Flux backend is shared with its Omarchy plugin. Anchor Shell
// supplies its own color tokens and keeps the same Flux IPC connection.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property alias backend: backend
  readonly property string themeText: [
    'background = "' + String(Color.background) + '"',
    'foreground = "' + String(Color.foreground) + '"',
    'accent = "' + String(Color.accent) + '"',
    'green = "' + String(Color.accent) + '"',
    'yellow = "' + String(Color.accent) + '"',
    'red = "' + String(Color.urgent) + '"'
  ].join("\n")

  FluxBackend { id: backend }
}
