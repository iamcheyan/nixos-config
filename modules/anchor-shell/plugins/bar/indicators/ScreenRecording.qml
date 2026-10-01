import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property bool recording: false
  property bool selecting: false
  readonly property var recorderService: root.bar && root.bar.shell
    && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor("anchor.screen-recording") : null

  active: recording || selecting
  activeText: "󰻂"
  inactiveText: "󰻂"
  activeTooltipText: recording ? "Stop recording" : "Select an area to record"
  inactiveTooltipText: "Screen Recording"

  function refresh() {
    if (root.recorderService) {
      root.recorderService.refresh()
      root.recording = root.recorderService.recording
      root.selecting = root.recorderService.starting
    }
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

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
  }

  onPressed: function() {
    if (root.bar) {
      if (root.recorderService) root.recorderService.toggle()
      else root.bar.run("${QUICKSHELL_ROOT}/plugins/screen-recording/bin/anchor-screen-recording toggle")
    }
  }
}
