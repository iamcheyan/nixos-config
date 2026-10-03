import QtQuick
import Quickshell
import Quickshell.Io
import "NightlightModel.js" as NightlightModel

// Night light is global, not per-monitor: wlroots hands each output's gamma
// ramp to exactly one client, so a second filter instance is refused and a
// per-monitor split would leave one screen unfiltered. The panel, the bar
// indicator, and `omarchy display nightlight` all drive this one service.
Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  // Keep in sync with bin/omarchy-display-nightlight, which applies the same
  // stops for callers outside the shell (keybindings, menu, ssh).
  readonly property int nightTemperature: 4000
  readonly property int dayTemperature: 6500

  property bool stateLoaded: false
  property int temperature: dayTemperature
  readonly property bool enabled: stateLoaded && NightlightModel.isNightlight(temperature)

  // A slower drag would otherwise spawn one wlsunset per notched value; keep
  // only the newest target and apply it when the running process exits.
  property bool applying: false
  property int pendingTemperature: -1

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function setNightlight(value) {
    applyTemperature(value ? nightTemperature : dayTemperature)
  }

  function toggle() {
    setNightlight(!enabled)
  }

  function setTemperature(value) {
    applyTemperature(NightlightModel.clampTemperature(value))
  }

  function adjustTemperature(delta) {
    applyTemperature(NightlightModel.clampTemperature(root.temperature + delta * 250))
  }

  function applyTemperature(value) {
    var next = NightlightModel.clampTemperature(value)
    // Publish immediately so the slider and indicator track the drag; the
    // process result reconciles us if the compositor disagrees.
    root.temperature = next
    root.stateLoaded = true

    if (applyProc.running) {
      root.pendingTemperature = next
      return
    }
    runApply(next)
  }

  function runApply(value) {
    root.applying = true
    applyProc.command = ["omarchy-display-nightlight", String(value)]
    applyProc.running = true
  }

  Process {
    id: statusProc
    command: ["omarchy-display-nightlight", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = NightlightModel.parseStatus(text)
        if (parsed !== null) root.temperature = parsed
        root.stateLoaded = true
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.stateLoaded = true
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = NightlightModel.parseStatus(text)
        if (parsed !== null) root.temperature = parsed
      }
    }
    onExited: function() {
      root.applying = false
      if (root.pendingTemperature >= 0) {
        var next = root.pendingTemperature
        root.pendingTemperature = -1
        root.runApply(next)
        return
      }
      root.refresh()
    }
  }

  Component.onCompleted: refresh()

  IpcHandler {
    target: "nightlight"

    function status(): string {
      return JSON.stringify({ enabled: root.enabled, temperature: root.temperature })
    }

    function refresh(): void {
      root.refresh()
    }

    function enable(): string {
      root.setNightlight(true)
      return "enabled"
    }

    function disable(): string {
      root.setNightlight(false)
      return "disabled"
    }

    function toggle(): string {
      var enabling = !root.enabled
      root.setNightlight(enabling)
      return enabling ? "enabled" : "disabled"
    }

    function setTemperature(temperature: string): string {
      root.setTemperature(Number(temperature))
      return String(root.temperature)
    }
  }
}
