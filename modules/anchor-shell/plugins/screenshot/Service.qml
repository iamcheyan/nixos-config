import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: service

  property var shell: null
  property bool capturing: false
  property bool selecting: false
  property string captureDir: ""
  property string requestId: ""
  property int capturesFinished: 0
  property int captureCount: Quickshell.screens.length
  property string captureScript: Quickshell.env("HOME") + "/.config/labwc/scripts/omarchy-capture-frozen"

  function begin() {
    if (capturing || selecting || Quickshell.screens.length === 0) return "busy"
    requestId = String(Date.now())
    captureDir = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
      + "/anchor-frozen-screenshot-" + requestId
    capturesFinished = 0
    captureCount = Quickshell.screens.length
    mkdirProc.command = ["mkdir", "-p", captureDir]
    mkdirProc.running = true
    return "started"
  }

  function capturePath(name) {
    return captureDir + "/" + name.replace(/[^A-Za-z0-9_.-]/g, "_") + ".png"
  }

  function captureFinished(exitCode) {
    if (exitCode !== 0) {
      console.warn("screenshot: failed to capture output")
      finish()
      return
    }
    capturesFinished++
    if (capturesFinished >= captureCount) {
      capturing = false
      closePopups()
      selecting = true
    }
  }

  function closePopups() {
    var bar = shell ? shell.bar : null
    if (bar && bar.activePopout) {
      var popup = bar.activePopout
      if (popup && typeof popup.close === "function") popup.close()
    }
    if (shell && shell.openPanelIds) {
      var ids = []
      for (var id in shell.openPanelIds) ids.push(id)
      for (var i = 0; i < ids.length; i++) shell.hide(ids[i])
    }
  }

  function finish() {
    selecting = false
    capturing = false
    if (captureDir !== "") Quickshell.execDetached(["rm", "-rf", captureDir])
    captureDir = ""
  }

  function copyRegion(screenName, x, y, width, height, scale) {
    var source = capturePath(screenName)
    Quickshell.execDetached([captureScript, source, String(Math.round(x * scale)),
      String(Math.round(y * scale)), String(Math.round(width * scale)),
      String(Math.round(height * scale)), "copy-save"])
    // The helper owns the frozen files until it has cropped and copied them.
    selecting = false
    captureDir = ""
  }

  Process {
    id: mkdirProc
    onExited: function(exitCode) {
      if (exitCode !== 0) { service.finish(); return }
      service.capturing = true
    }
  }

  Variants {
    model: service.capturing ? Quickshell.screens : []
    Process {
      required property var modelData
      command: ["grim", "-o", String(modelData.name), service.capturePath(String(modelData.name))]
      onExited: function(exitCode) { service.captureFinished(exitCode) }
      Component.onCompleted: running = true
    }
  }

  Variants {
    model: Quickshell.screens
    FrozenSurface {
      host: service
    }
  }

  IpcHandler {
    target: "omarchy.screenshot"
    function begin(): string { return service.begin() }
    function cancel(): void { service.finish() }
    function status(): string {
      return JSON.stringify({ capturing: service.capturing, selecting: service.selecting,
        capturesFinished: service.capturesFinished, captureCount: service.captureCount })
    }
  }
}
