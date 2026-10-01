pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: service

  property string integrationPath: ""
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property bool recording: false
  property bool starting: false
  readonly property string recorderCommand: (Quickshell.env("QUICKSHELL_ROOT") || "")
    + "/plugins/screen-recording/bin/anchor-screen-recording"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (starting || startProc.running || stopProc.running) return
    if (recording) stopProc.running = true
    else {
      starting = true
      startProc.running = true
    }
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: service.refresh()
  }

  Process {
    id: statusProc
    command: [service.recorderCommand, "status"]
    stdout: SplitParser {
      onRead: function(line) {
        service.recording = String(line).trim() === "yes"
      }
    }
  }

  Process {
    id: startProc
    command: [service.recorderCommand, "start"]
    onExited: function() {
      service.starting = false
      service.refresh()
    }
  }

  Process {
    id: stopProc
    command: [service.recorderCommand, "stop"]
    onExited: service.refresh()
  }
}
