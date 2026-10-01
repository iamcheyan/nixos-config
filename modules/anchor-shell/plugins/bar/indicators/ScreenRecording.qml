import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  property bool recording: false
  property bool selecting: false
  property bool paused: false
  property bool menuOpen: false
  readonly property var recorderService: root.bar && root.bar.shell
    && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor("anchor.screen-recording") : null
  readonly property var barScreen: (root.QsWindow && root.QsWindow.window && root.QsWindow.window.screen)
    ? root.QsWindow.window.screen
    : (Window.window && Window.window.screen ? Window.window.screen : null)
  readonly property string barOutputName: barScreen ? String(barScreen.name || "") : ""

  active: recording || selecting
  activeText: "󰻂"
  inactiveText: "󰻂"
  activeTooltipText: paused ? "Recording paused"
    : recording ? "Stop recording"
    : selecting ? "Select an area, then wait for the countdown"
    : "Select an area to record"
  inactiveTooltipText: "Screen Recording"

  function close() { root.menuOpen = false }

  function holdIndicatorReveal(held) {
    if (root.indicatorHost && root.indicatorHost.setIndicatorItemHovered)
      root.indicatorHost.setIndicatorItemHovered(held)
  }

  function refresh() {
    if (root.recorderService) {
      root.recorderService.refresh()
      root.recording = !!root.recorderService.recording
      root.selecting = !!root.recorderService.starting
      root.paused = !!root.recorderService.paused
    }
  }

  function startRegion() {
    root.menuOpen = false
    if (root.recorderService) root.recorderService.startRegion()
    else root.runRecorder(["start", "--region"])
  }

  function activeOutputName() {
    var output = ""
    if (root.recorderService && typeof root.recorderService.focusedOutputName === "function")
      output = String(root.recorderService.focusedOutputName() || "")
    if (!output) output = root.barOutputName
    return output
  }

  function startFullscreen() {
    root.menuOpen = false
    var output = root.activeOutputName()
    if (root.recorderService) root.recorderService.startFullscreen(output)
    else if (output) root.runRecorder(["start", "--fullscreen", "--output", output])
    else root.runRecorder(["start", "--fullscreen"])
  }

  function stopRecording() {
    root.menuOpen = false
    if (root.recorderService) root.recorderService.stop()
    else root.runRecorder(["stop"])
  }

  function runRecorder(args) {
    var rootDir = Quickshell.env("QUICKSHELL_ROOT") || Quickshell.shellDir
    var command = rootDir + "/plugins/screen-recording/bin/anchor-screen-recording"
    Quickshell.execDetached([command].concat(args))
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()
  onMenuOpenChanged: root.holdIndicatorReveal(root.menuOpen)

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Connections {
    target: root.recorderService
    ignoreUnknownSignals: true
    function onRecordingChanged() {
      root.recording = !!root.recorderService.recording
    }
    function onStartingChanged() {
      root.selecting = !!root.recorderService.starting
    }
    function onPausedChanged() {
      root.paused = !!root.recorderService.paused
    }
    function onSessionChanged() {
      root.refresh()
    }
  }

  onPressed: function(button) {
    if (root.recording || root.selecting) {
      root.stopRecording()
      return
    }
    if (button === Qt.RightButton) {
      root.menuOpen = !root.menuOpen
      return
    }
    root.startRegion()
  }

  PopupCard {
    id: menu
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(240))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.space(4)

      Button {
        width: parent.width
        leftAlign: true
        iconText: "󰍹"
        text: "Record active display"
        tooltipText: root.activeOutputName()
          ? "Record " + root.activeOutputName()
          : "Record the focused display"
        onClicked: root.startFullscreen()
      }

      Button {
        width: parent.width
        leftAlign: true
        iconText: "󰒉"
        text: "Record a region"
        tooltipText: "Drag to choose what to record"
        onClicked: root.startRegion()
      }
    }
  }
}
