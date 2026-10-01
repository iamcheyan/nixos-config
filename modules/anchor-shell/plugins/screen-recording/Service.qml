pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: service

  property string integrationPath: ""
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null

  property string session: "idle"
  property string mode: "region"
  property string targetOutput: ""
  property real regionX: 0
  property real regionY: 0
  property real regionW: 0
  property real regionH: 0
  property int countdown: 0
  property int elapsedSec: 0
  property string outputPath: ""

  readonly property bool recording: session === "recording" || session === "paused"
  readonly property bool paused: session === "paused"
  readonly property bool starting: session === "selecting" || session === "countdown" || session === "starting"
  readonly property string elapsedText: {
    var m = Math.floor(service.elapsedSec / 60)
    var s = service.elapsedSec % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }
  readonly property string pluginDir: (manifest && manifest.__sourceDir)
    ? String(manifest.__sourceDir)
    : ((Quickshell.env("QUICKSHELL_ROOT") || Quickshell.shellDir) + "/plugins/screen-recording")
  readonly property string recorderCommand: pluginDir + "/bin/anchor-screen-recording"

  function focusedOutputName() {
    var active = ToplevelManager.activeToplevel
    if (active) {
      var screens = active.screens || []
      if (screens.length > 0 && screens[0] && screens[0].name)
        return String(screens[0].name)
      if (active.screen && active.screen.name)
        return String(active.screen.name)
    }
    if (Quickshell.screens.length === 1 && Quickshell.screens[0])
      return String(Quickshell.screens[0].name || "")
    return ""
  }

  function screenByName(name) {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === String(name || ""))
        return screens[i]
    }
    return null
  }

  function resetSession() {
    countdownTimer.stop()
    elapsedTimer.stop()
    if (startProc.running) startProc.running = false
    service.session = "idle"
    service.mode = "region"
    service.targetOutput = ""
    service.regionX = 0
    service.regionY = 0
    service.regionW = 0
    service.regionH = 0
    service.countdown = 0
    service.elapsedSec = 0
    service.outputPath = ""
  }

  function startRegion() {
    if (service.session !== "idle") return
    service.mode = "region"
    service.targetOutput = ""
    service.regionX = 0
    service.regionY = 0
    service.regionW = 0
    service.regionH = 0
    service.session = "selecting"
  }

  function startFullscreen(outputName) {
    if (service.session !== "idle") return
    var output = String(outputName || "").trim()
    if (!output) output = service.focusedOutputName()
    var screen = service.screenByName(output)
    if (!screen && Quickshell.screens.length === 1)
      screen = Quickshell.screens[0]
    if (!screen) return
    service.mode = "fullscreen"
    service.targetOutput = String(screen.name || output)
    service.regionX = 0
    service.regionY = 0
    service.regionW = screen.width
    service.regionH = screen.height
    service.beginCountdown()
  }

  function confirmRegion(outputName, x, y, w, h) {
    if (service.session !== "selecting") return
    if (w < 8 || h < 8) return
    service.mode = "region"
    service.targetOutput = String(outputName || "")
    service.regionX = Math.round(x)
    service.regionY = Math.round(y)
    service.regionW = Math.round(w)
    service.regionH = Math.round(h)
    service.beginCountdown()
  }

  function beginCountdown() {
    service.session = "countdown"
    service.countdown = 3
    service.elapsedSec = 0
    countdownTimer.restart()
  }

  function startBackend() {
    var args = ["start", "--quiet"]
    if (service.mode === "fullscreen" && service.targetOutput) {
      args.push("--fullscreen", "--output", service.targetOutput)
    } else {
      var screen = service.screenByName(service.targetOutput)
      var gx = Math.round(service.regionX + (screen ? screen.x : 0))
      var gy = Math.round(service.regionY + (screen ? screen.y : 0))
      args.push("--region", gx + "," + gy + " " + Math.round(service.regionW) + "x" + Math.round(service.regionH))
    }
    service.session = "starting"
    startProc.command = [service.recorderCommand].concat(args)
    startProc.running = true
  }

  function togglePause() {
    if (service.session !== "recording" && service.session !== "paused") return
    Quickshell.execDetached([service.recorderCommand, "pause"])
    if (service.session === "recording") {
      service.session = "paused"
      elapsedTimer.stop()
    } else {
      service.session = "recording"
      elapsedTimer.start()
    }
  }

  function stop() {
    if (service.session === "idle") return
    if (service.session === "selecting" || service.session === "countdown") {
      service.cancel()
      return
    }
    elapsedTimer.stop()
    countdownTimer.stop()
    if (startProc.running) startProc.running = false
    Quickshell.execDetached([service.recorderCommand, "stop"])
    service.resetSession()
  }

  function cancel() {
    if (service.session === "idle") return
    if (service.session === "recording" || service.session === "paused" || service.session === "starting")
      Quickshell.execDetached([service.recorderCommand, "stop"])
    service.resetSession()
  }

  function toggle() {
    if (service.session === "idle") service.startRegion()
    else service.stop()
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  Component.onCompleted: refresh()

  Timer {
    id: countdownTimer
    interval: 1000
    repeat: true
    onTriggered: {
      if (service.countdown > 1) {
        service.countdown -= 1
        return
      }
      countdownTimer.stop()
      service.countdown = 0
      service.startBackend()
    }
  }

  Timer {
    id: elapsedTimer
    interval: 1000
    repeat: true
    onTriggered: service.elapsedSec += 1
  }

  Timer {
    interval: 1000
    repeat: true
    running: service.session === "recording" || service.session === "paused" || service.session === "starting"
    onTriggered: service.refresh()
  }

  Process {
    id: startProc
    command: [service.recorderCommand, "status"]
    stdout: StdioCollector {
      id: startOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("screen-recording: start failed", exitCode)
        service.resetSession()
        return
      }
      var path = String(startOut.text || "").trim().split("\n").filter(function(line) {
        return line.length > 0
      }).pop() || ""
      service.outputPath = path
      service.session = "recording"
      service.elapsedSec = 0
      elapsedTimer.start()
    }
  }

  Process {
    id: statusProc
    command: [service.recorderCommand, "status"]
    stdout: SplitParser {
      onRead: function(line) {
        var state = String(line).trim()
        var alive = state === "recording" || state === "yes"
        if (alive) return
        if (service.session === "recording" || service.session === "paused")
          service.resetSession()
      }
    }
  }

  Variants {
    model: Quickshell.screens
    RecordingSurface {
      host: service
    }
  }
}
