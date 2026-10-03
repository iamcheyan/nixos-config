import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  property string runtimeDir: {
    const xdg = Quickshell.env("XDG_RUNTIME_DIR")
    return xdg && xdg.length > 0 ? xdg + "/voxtype" : ""
  }
  property string daemonState: "idle"
  property int spinnerFrame: 0
  property real recordingMix: 0.0

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  property bool recordingAnimationEnabled: setting("recordingAnimation", true) === true
  property bool middleMouseToggleEnabled: setting("middleMouseToggle", false) === true
  readonly property color normalForeground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color recordingYellow: "#f2c94c"
  readonly property var spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  active: daemonState === "recording" || daemonState === "transcribing"
  activeText: daemonState === "transcribing" ? spinnerFrames[spinnerFrame] : "󰍬"
  inactiveText: "󰍬"
  activeTooltipText: daemonState === "recording" ? "Voxtype recording"
    : daemonState === "transcribing" ? "Voxtype transcribing"
    : "Voxtype"
  inactiveTooltipText: "Voxtype"

  foreground: daemonState === "recording" && recordingAnimationEnabled
    ? blendColor(normalForeground, recordingYellow, recordingMix)
    : normalForeground

  function blendColor(from, to, amount) {
    var t = Math.max(0, Math.min(1, amount))
    return Qt.rgba(
      from.r + (to.r - from.r) * t,
      from.g + (to.g - from.g) * t,
      from.b + (to.b - from.b) * t,
      from.a + (to.a - from.a) * t
    )
  }

  function holdIndicatorReveal(held) {
    if (root.indicatorHost && root.indicatorHost.setIndicatorItemHovered) {
      root.indicatorHost.setIndicatorItemHovered(held)
    }
  }

  onOpenedChanged: root.holdIndicatorReveal(root.opened)

  function setRecordingAnimationEnabled(enabled) {
    root.recordingAnimationEnabled = enabled
  }

  function setMiddleMouseToggleEnabled(enabled) {
    root.middleMouseToggleEnabled = enabled
  }

  FileView {
    id: stateFile
    path: root.runtimeDir + "/state"
    watchChanges: true
    printErrors: false
    onLoaded: root.daemonState = (text() || "idle").trim().toLowerCase()
    onLoadFailed: root.daemonState = "idle"
    onFileChanged: reload()
  }

  Timer {
    interval: 150
    repeat: true
    running: root.runtimeDir.length > 0
    onTriggered: stateFile.reload()
  }

  Timer {
    interval: 120
    repeat: true
    running: root.daemonState === "transcribing"
    onTriggered: root.spinnerFrame = (root.spinnerFrame + 1) % root.spinnerFrames.length
  }

  SequentialAnimation {
    running: root.daemonState === "recording" && root.recordingAnimationEnabled
    loops: Animation.Infinite
    NumberAnimation {
      target: root
      property: "recordingMix"
      from: 0.0
      to: 1.0
      duration: 1100
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root
      property: "recordingMix"
      from: 1.0
      to: 0.0
      duration: 1100
      easing.type: Easing.InOutSine
    }
  }

  onDaemonStateChanged: {
    if (root.daemonState !== "transcribing") root.spinnerFrame = 0
    if (root.daemonState !== "recording") root.recordingMix = 0.0
  }

  onRecordingAnimationEnabledChanged: {
    if (!root.recordingAnimationEnabled) root.recordingMix = 0.0
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = root
    panelLoader.item.hostWidget = root
  }

  function openPanel() {
    if (panelLoader.item) {
      panelLoader.item.open()
      return
    }
    panelLoader.active = true
    Qt.callLater(function() {
      if (panelLoader.item) panelLoader.item.open()
    })
  }

  function closePanel() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (root.opened) root.closePanel()
    else root.openPanel()
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: false
    source: Qt.resolvedUrl("../../voxtype/VoxtypePanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  onPressed: function(button) {
    if (button === Qt.LeftButton) {
      root.togglePanel()
    } else if (button === Qt.RightButton) {
      if (root.bar) root.bar.run("omarchy-voxtype-config")
    } else if (button === Qt.MiddleButton) {
      Quickshell.execDetached(["voxtype", "record", "toggle"])
    }
  }
}
