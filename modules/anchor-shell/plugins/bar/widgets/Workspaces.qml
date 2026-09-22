import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  readonly property bool labwcSession:
    String(Quickshell.env("XDG_CURRENT_DESKTOP") || "").split(":").indexOf("labwc") !== -1
    || String(Quickshell.env("XDG_SESSION_DESKTOP") || "").split(":").indexOf("labwc") !== -1
  // PanelWindow is exposed through Quickshell's attached window in some
  // Loader paths. Prefer Qt's window binding, but keep that runtime binding as
  // a fallback so the per-output state path is never empty.
  readonly property var hostWindow: (root.QsWindow && root.QsWindow.window) ? root.QsWindow.window : Window.window
  readonly property var hostScreen: (hostWindow && hostWindow.screen) ? hostWindow.screen : (Quickshell.screens.length === 1 ? Quickshell.screens[0] : null)
  readonly property string outputName:
    hostScreen ? String(hostScreen.name || "") : ""
  readonly property string runtimeDir:
    Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string stateDir:
    root.runtimeDir !== "" ? root.runtimeDir + "/labwc" : ""
  readonly property string statePath:
    root.labwcSession && root.stateDir !== "" && root.outputName !== ""
      ? (root.stateDir + "/workspace-" + root.outputName) : ""
  readonly property string gotoPath:
    root.statePath !== "" ? (root.statePath + ".goto") : ""
  property int labwcCurrent: 1
  property var labwcWorkspaceIds: [1, 2, 3, 4]

  function parseLabwcState(text) {
    var trimmed = String(text || "").trim()
    if (!trimmed) return

    var parts = trimmed.split(/\s+/)
    var current = 0
    var count = 0
    if (parts.length >= 2 && /^\d+$/.test(parts[0]) && /^\d+$/.test(parts[1])) {
      current = Number(parts[0])
      count = Number(parts[1])
    } else {
      // Older bridge wrote "<localized-name> <count>", e.g. "ワークスペース 2 4".
      var match = trimmed.match(/(\d+)\s+(\d+)$/)
      if (!match) return
      current = Number(match[1])
      count = Number(match[2])
    }

    if (current >= 1 && current <= 10) root.labwcCurrent = current
    if (count >= 1 && count <= 10 && count !== root.labwcWorkspaceIds.length) {
      var ids = []
      for (var i = 1; i <= count; i++) ids.push(i)
      root.labwcWorkspaceIds = ids
    }
  }

  function loadLabwcWorkspace() {
    if (!root.statePath) return
    root.parseLabwcState(labwcState.text())
  }

  function requestLabwcWorkspace(id) {
    if (!root.labwcSession || !root.gotoPath) return
    Quickshell.execDetached([
      "sh", "-c",
      "printf '%s\\n' \"$1\" > \"$2.tmp.$$\" && mv -f \"$2.tmp.$$\" \"$2\"",
      "labwc-goto",
      String(id),
      root.gotoPath
    ])
  }

  FileView {
    id: labwcState
    path: root.statePath
    watchChanges: root.labwcSession && root.statePath !== ""
    printErrors: false
    onLoaded: root.loadLabwcWorkspace()
    onFileChanged: reload()
  }

  // FileView misses create/rename of the atomically replaced state file, and
  // the bar surface can bind its screen name after the first load attempt.
  Timer {
    interval: 200
    running: root.labwcSession && root.statePath !== ""
    repeat: true
    onTriggered: labwcState.reload()
  }

  onOutputNameChanged: if (root.statePath) labwcState.reload()
  onStatePathChanged: if (root.statePath) labwcState.reload()

  function workspaceById(id) {
    if (root.labwcSession) return null
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  readonly property var activeWorkspaceIds: {
    if (root.labwcSession) return root.labwcWorkspaceIds
    var ids = [1, 2, 3, 4]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function workspaceIds() {
    return root.activeWorkspaceIds
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.activeWorkspaceIds.length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.activeWorkspaceIds

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: root.labwcSession
          ? Number(root.labwcCurrent) === Number(modelData)
          : (Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData)

        bar: root.bar
        // Match Omarchy's original indicator: the focused workspace is shown
        // as the small square glyph, while the other slots keep their number.
        text: focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        dimmed: root.labwcSession ? !focused : !(occupied || focused)
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() {
          if (root.labwcSession) root.requestLabwcWorkspace(modelData)
          else root.focusWorkspace(modelData)
        }
      }
    }
  }
}
