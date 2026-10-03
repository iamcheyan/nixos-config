import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.monitor"
  ipcTarget: "omarchy.monitor"
  manageIpc: false

  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the brightness + state methods below.

  // ---------------------------------------------------------------- state
  //
  // Every panel instance is mounted once per monitor (one bar surface per
  // screen), but all of them drive the *same* underlying outputs. `targetName`
  // is the output this instance's bar sits on; it scopes the per-display
  // sections so clicking the icon on the 4K screen edits the 4K screen.
  readonly property var ownScreen: (root.QsWindow && root.QsWindow.window && root.QsWindow.window.screen)
    ? root.QsWindow.window.screen : null
  readonly property string ownScreenName: ownScreen ? String(ownScreen.name || "") : ""

  property string session: "labwc"
  property var displays: []
  property string targetName: ""
  property int enabledDisplayCount: 0
  property bool stateLoaded: false

  readonly property var target: Model.findDisplay(displays, targetName)
  readonly property bool targetEnabled: target ? target.enabled !== false : false
  readonly property bool multiDisplay: displays.length > 1
  readonly property var targetResolutions: Model.distinctResolutions(target ? target.modes : [])
  readonly property var targetRefreshes: Model.refreshesFor(
    target ? target.modes : [],
    Model.resolutionKey(Model.currentMode(target)))
  property string activeTab: "display"

  // ---------------------------------------------------------------- brightness
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // ---------------------------------------------------------------- text size
  // Curated macOS-style notches (px). The panel snaps to these stops; the CLI
  // (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1
  property bool reflowingText: false

  // ---------------------------------------------------------------- scale
  readonly property var scalePresets: ["1", "1.25", "1.5", "2", "2.5", "3"]
  readonly property var scaleValues: {
    if (!target) return scalePresets
    // Hyprland only accepts scales that divide the mode evenly; wlroots takes
    // any factor, so the full preset row stays available there.
    if (session === "hyprland")
      return Model.availableScales(scalePresets, target.width, target.height)
    return scalePresets
  }
  property int scalePreviewIndex: -1

  // ---------------------------------------------------------------- rotation
  readonly property var rotationValues: Model.ROTATIONS
  property int rotationPreviewIndex: -1

  // ---------------------------------------------------------------- night mode
  readonly property var nightlightService: bar?.shell?.firstPartyServiceFor("omarchy.nightlight")
  readonly property bool nightEnabled: nightlightService ? nightlightService.enabled === true : false
  readonly property int nightTemperature: nightlightService ? nightlightService.temperature : 6500
  readonly property var temperatureStops: Model.temperatureStops()
  property int temperaturePreviewIndex: -1

  // ---------------------------------------------------------------- cursor
  // Sections, in the order j/k walks them:
  //   "brightness" - lone slider, index sentinel -1
  //   "night"      - lone slider, index sentinel -1
  //   "textsize"   - lone slider, index sentinel -1
  //   "resolution" - searchable resolution dropdown
  //   "refresh"    - lone dropdown
  //   "scale"      - horizontal preset row
  //   "rotation"   - horizontal preset row
  //   "displays"   - vertical list of connected outputs
  readonly property var visibleSections: {
    var list = []
    if (activeTab === "display") {
      if (targetEnabled) {
        list.push("resolution")
        list.push("scale")
      }
    } else if (activeTab === "comfort") {
      if (brightnessAvailable) list.push("brightness")
      list.push("night")
      list.push("textsize")
      if (targetEnabled && targetRefreshes.length > 1) list.push("refresh")
      if (targetEnabled) list.push("rotation")
      if (displays.length > 1) list.push("displays")
    }
    return list
  }

  function activateTab(name) {
    if (resolutionDropdown.popupOpen) resolutionDropdown.close()
    activeTab = name
    var sections = visibleSections
    focusSection = sections.length > 0 ? sections[0] : "scale"
    selectedIndex = sectionFirstIndex(focusSection)
    cursorActive = false
  }

  function appearancePageHeight() {
    var heights = [heroRow.implicitHeight, tabRow.implicitHeight, Style.space(4)]
    var count = heights.length
    function add(height) { heights.push(height); count++ }
    if (brightnessAvailable) { add(brightnessSeparator.implicitHeight); add(brightnessSection.implicitHeight) }
    add(nightSeparator.implicitHeight); add(nightSection.implicitHeight)
    add(textSizeSeparator.implicitHeight); add(textSizeSection.implicitHeight)
    if (targetEnabled && targetRefreshes.length > 1) add(refreshSection.implicitHeight)
    if (targetEnabled) { add(rotationSeparator.implicitHeight); add(rotationSection.implicitHeight) }
    if (displays.length > 1) { add(displaysSeparator.implicitHeight); add(displaysSection.implicitHeight) }
    return heights.reduce(function(total, height) { return total + height }, 0)
      + Math.max(0, count - 1) * panelColumn.spacing
  }

  function arrangementHeight() {
    // The appearance page sets the shared card height; use the remaining
    // space for the display map so both pages fill the same viewport.
    var fixed = heroRow.implicitHeight + tabRow.implicitHeight + Style.space(4)
      + layoutSeparator.implicitHeight + layoutHeader.implicitHeight + layoutSection.spacing
      + resolutionSeparator.implicitHeight + resolutionSection.implicitHeight
      + scaleSeparator.implicitHeight + scaleSection.implicitHeight
      + 8 * panelColumn.spacing
    return Math.max(Style.space(104), appearancePageHeight() - fixed)
  }

  function sectionCount(section) {
    if (section === "brightness" || section === "night" || section === "textsize") return 0
    if (section === "resolution") return 0
    if (section === "refresh") return targetRefreshes.length
    if (section === "scale") return scaleValues.length
    if (section === "rotation") return rotationValues.length
    if (section === "displays") return displays.length
    return 0
  }

  // Every option row is laid out horizontally and walked with h/l; only the
  // display list is a vertical list. Keeping this set explicit stops the
  // cursor from landing on an index no row is painted for.
  function sectionIsSingleRow(section) {
    return section !== "displays"
  }

  function currentResolutionIndex() {
    for (var i = 0; i < targetResolutions.length; i++) {
      if (targetResolutions[i].current) return i
    }
    return 0
  }

  function currentResolutionKey() {
    return Model.resolutionKey(Model.currentMode(target))
  }

  function currentRefreshIndex() {
    if (!target) return 0
    var mode = Model.currentMode(target)
    var index = Model.refreshIndex(targetRefreshes, mode ? mode.refresh : 0)
    return index < 0 ? 0 : index
  }

  function sectionFirstIndex(section) {
    if (section === "brightness" || section === "night" || section === "textsize") return -1
    if (section === "resolution") return -1
    if (section === "refresh") return currentRefreshIndex()
    if (section === "scale") {
      var scaleIndex = activeScaleIndex()
      return scaleIndex < 0 ? 0 : scaleIndex
    }
    if (section === "rotation") return Model.rotationIndex(target ? target.transform : "normal")
    return 0
  }

  property string focusSection: "scale"
  property int selectedIndex: 0
  property bool cursorActive: false

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        // Coming up from below — land on the last navigable row of the prev
        // section, or its sentinel for single-row sections.
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l walks the option rows. The three slider sections are excluded because
  // adjustBrightness/adjustTemperature own their horizontal motion, and the
  // display list is vertical.
  function moveCursorH(delta) {
    if (focusSection === "brightness" || focusSection === "night"
        || focusSection === "textsize" || !sectionIsSingleRow(focusSection)) return
    var count = sectionCount(focusSection)
    if (count <= 0) return
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > count - 1) next = count - 1
    selectedIndex = next
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness") return
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function adjustTemperature(delta) {
    if (focusSection !== "night") return
    if (!nightlightService) return
    // Slider runs day -> night while the underlying value counts down in
    // kelvin, so a rightward step lowers the temperature.
    var index = currentTemperatureIndex() - delta
    if (index < 0) index = 0
    if (index > temperatureStops.length - 1) index = temperatureStops.length - 1
    temperaturePreviewIndex = index
    setTemperature(temperatureStops[index])
  }

  // Space/Enter on the night row flips the filter, matching a click on the
  // switch. The slider pair is the section's other control, so the toggle is
  // the only unambiguous "activate this row" action.
  function toggleNightFromCursor() {
    if (focusSection !== "night") return
    setNightlight(!nightEnabled)
  }
  function activateCursor() {
    if (focusSection === "night") { toggleNightFromCursor(); return }
    if (focusSection === "resolution") {
      resolutionDropdown.toggle()
      return
    }
    if (focusSection === "refresh" && selectedIndex >= 0 && selectedIndex < targetRefreshes.length) {
      var refresh = targetRefreshes[selectedIndex]
      if (refresh && Model.refreshIndex(targetRefreshes, Model.currentMode(target).refresh) !== selectedIndex)
        setRefresh(refresh.mode)
      return
    }
    if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
      setScale(scaleValues[selectedIndex])
      return
    }
    if (focusSection === "rotation" && selectedIndex >= 0 && selectedIndex < rotationValues.length) {
      setRotation(rotationValues[selectedIndex])
      return
    }
    if (focusSection === "displays" && selectedIndex >= 0 && selectedIndex < displays.length) {
      var display = displays[selectedIndex]
      if (display) toggleDisplay(display.name, display.enabled)
    }
    // brightness / night / text size: the control is the action.
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (sectionIsSingleRow(focusSection)) {
      // Slider/toggle/dropdown sections use the -1 sentinel; the two preset
      // rows index into their own option lists.
      var options = sectionCount(focusSection)
      if (options === 0) selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= options) selectedIndex = 0
      return
    }
    var count = sectionCount(focusSection)
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height (lots of displays).
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  // ---------------------------------------------------------------- IPC

  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      session: root.session,
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.targetName,
      display: root.target,
      displays: root.displays
    })
  }

  IpcHandler {
    target: "omarchy.monitor"
    enabled: root.stateLoaded && root.displays.length > 0
      && root.ownScreenName === root.displays[0].name

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function state(): string { return root.stateIpc() }
    function refresh(): void { root.refresh() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  // ---------------------------------------------------------------- commands
  //
  // Every mutating call goes through one Process; `pendingCommand` holds the
  // newest invocation when a call arrives mid-flight, so fast slider and
  // preset interaction coalesces instead of piling up processes.

  property var pendingCommand: null
  property bool commandRunning: false

  function runCommand(argv, after) {
    pendingAfter = after || null
    if (commandRunning) {
      pendingCommand = argv
      return
    }
    startCommand(argv)
  }

  property var pendingAfter: null

  function startCommand(argv) {
    commandProc.command = argv
    commandRunning = true
    commandProc.running = true
  }

  Process {
    id: commandProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (root.pendingCommand !== null) {
        var next = root.pendingCommand
        root.pendingCommand = null
        root.startCommand(next)
        return
      }
      root.commandRunning = false
      var after = root.pendingAfter
      root.pendingAfter = null
      if (after) after(exitCode)
    }
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    probeBrightness()
  }

  // The command is rebuilt on every probe instead of relying on the `command`
  // binding: targetName resolves only after the first state read, and setting
  // `running` before that rebinding lands would launch the stale
  // empty-monitor command.
  function probeBrightness() {
    if (brightnessProc.running || root.targetName === "") return
    brightnessProc.command = ["omarchy-brightness-display", "--monitor", root.targetName]
    brightnessProc.running = true
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.targetName, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
  }

  // ---- Display changes (resolution, refresh, scale, rotation, enable) ----
  //
  // One helper drives every output change so the argument set is built and
  // validated in a single place. `--persist` records the result so the layout
  // survives a reboot.
  function randrArgs(output) {
    return ["omarchy-display-randr", "--output", output, "--persist"]
  }

  function setResolution(resolution) {
    if (!resolution || !target) return
    runCommand(randrArgs(target.name).concat([
      "--mode", resolution.key,
      "--position", target.x + "," + target.y
    ]), function() { root.refresh() })
  }

  function setRefresh(mode) {
    if (!mode || !target) return
    runCommand(randrArgs(target.name).concat([
      "--mode", Model.modeArgument(mode),
      "--position", target.x + "," + target.y
    ]), function() { root.refresh() })
  }

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function activeScaleIndex() {
    if (!target) return -1
    var current = Model.normalizeScale(target.scale)
    for (var i = 0; i < scaleValues.length; i++) {
      if (Model.normalizeScale(scaleValues[i]) === current) return i
    }
    return -1
  }

  function effectiveScale(scale) {
    if (!target) return Model.normalizeScale(scale)
    if (session === "hyprland")
      return Model.cleanScale(scale, target.width, target.height)
    return Model.normalizeScale(scale)
  }

  function setScale(scale) {
    if (!target) return
    scalePreviewIndex = -1
    runCommand(randrArgs(target.name).concat(["--scale", String(scale)]), function() { root.refresh() })
  }

  function previewScale(index) {
    scalePreviewIndex = index
  }

  function currentScaleLabel() {
    if (scalePreviewIndex >= 0 && scalePreviewIndex < scaleValues.length)
      return effectiveScale(scaleValues[scalePreviewIndex]) + "x"
    if (!target) return ""
    return Model.normalizeScale(target.scale) + "x"
  }

  function setRotation(transform) {
    if (!target) return
    rotationPreviewIndex = -1
    runCommand(randrArgs(target.name).concat(["--transform", String(transform)]), function() { root.refresh() })
  }

  function currentRotationIndex() {
    if (rotationPreviewIndex >= 0) return rotationPreviewIndex
    return Model.rotationIndex(target ? target.transform : "normal")
  }

  function currentRotationLabel() {
    return target ? Model.rotationLabel(target.transform) : "—"
  }

  function toggleDisplay(name, enabled) {
    if (!name || !stateLoaded) return
    if (enabled && root.enabledDisplayCount <= 1) return
    runCommand(randrArgs(name).concat([enabled ? "--disable" : "--enable"]), function() { root.refresh() })
  }

  function setDisplayPosition(name, x, y) {
    if (!name || !stateLoaded) return
    runCommand(randrArgs(name).concat(["--position", Math.round(x) + "," + Math.round(y)]),
      function() { root.refresh() })
  }

  // ---- Night mode ----

  function setNightlight(value) {
    if (!nightlightService) return
    if (value) nightlightService.setNightlight(true)
    else nightlightService.setNightlight(false)
  }

  function setTemperature(value) {
    if (!nightlightService) return
    nightlightService.setTemperature(value)
  }

  function currentTemperatureIndex() {
    if (temperaturePreviewIndex >= 0) return temperaturePreviewIndex
    var value = Model.clampTemperature(nightlightService ? nightlightService.temperature : 6500)
    for (var i = 0; i < temperatureStops.length; i++) {
      if (temperatureStops[i] === value) return i
    }
    return 0
  }

  function displayedTemperature() {
    if (temperaturePreviewIndex >= 0) return temperatureStops[temperaturePreviewIndex]
    return Model.clampTemperature(nightlightService ? nightlightService.temperature : 6500)
  }

  function nightSummary() {
    if (!nightlightService) return "Unavailable"
    if (!nightEnabled) return "Day light"
    return Model.temperatureLabel(nightTemperature)
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----

  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section.
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  // ---------------------------------------------------------------- lifecycle

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOwnScreenNameChanged: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      focusSection = visibleSections.length > 0 ? visibleSections[0] : "scale"
      selectedIndex = sectionFirstIndex(focusSection)
      cursorActive = false
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: {
    clampCursor()
  }
  onTargetChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onTargetResolutionsChanged: clampCursor()
  onTargetRefreshesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Poll only while the panel is open; external changes (another tool moving
  // outputs, a hotplug) are folded in at open-time and every few seconds then.
  Timer {
    interval: 4000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["omarchy-display-randr", "--json", "--output", root.ownScreenName]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseState(text)
        root.session = parsed.session
        root.displays = parsed.displays
        root.enabledDisplayCount = parsed.enabledDisplayCount
        // Prefer this bar's own screen; fall back to whatever the helper
        // picked so a single-monitor install still has a target.
        var scoped = Model.findDisplay(parsed.displays, root.ownScreenName)
        root.targetName = scoped ? scoped.name : parsed.focused
        root.stateLoaded = true
      }
    }
    onExited: function() { root.stateLoaded = true }
  }

  // Brightness probes the *target* output, so each monitor's slider reads its
  // own backlight / DDC level.
  Process {
    id: brightnessProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        var parsed = parseInt(raw, 10)
        root.brightnessAvailable = raw !== "" && isFinite(parsed)
        if (root.brightnessAvailable) root.brightnessPercent = Model.clampBrightness(parsed)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.brightnessAvailable = false
    }
  }

  // Re-probe brightness whenever the target output changes.
  onTargetNameChanged: probeBrightness()

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Do NOT call refresh() after a brightness set completes. The local
    // brightnessPercent we just wrote is authoritative; re-reading via
    // `omarchy-brightness-display` races the hardware/driver and can return an
    // empty string, which the parser then coerces to 0 — visible as a "bounce
    // to zero" after h/l keypresses.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once Style's base-size catches up to the pending choice, drop the preview
  // so the slider tracks the live value again.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  // A drag of the night slider should not leave a stale preview behind once
  // the service reports the settled value.
  Connections {
    target: root.nightlightService
    ignoreUnknownSignals: true
    function onTemperatureChanged() {
      if (root.temperaturePreviewIndex >= 0
          && root.temperatureStops[root.temperaturePreviewIndex] === root.nightTemperature)
        root.temperaturePreviewIndex = -1
    }
  }

  Connections {
    target: root.nightlightService
    ignoreUnknownSignals: true
    function onEnabledChanged() { root.clampCursor() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(620))
    // Match the two pages at a compact height; the layout preview grows to
    // use the space left after resolution and scale controls.
    contentHeight: panel.fittedContentHeight(root.appearancePageHeight() + Style.space(4), Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: resolutionDropdown.popupOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)
          else if (root.focusSection === "night") root.adjustTemperature(dx)
          else if (root.focusSection === "textsize") root.adjustTextSize(dx)
          else root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "1") root.activateTab("display")
        else if (text === "2") root.activateTab("comfort")
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(9)

          // ---------- Hero: display icon · title/status ----------
          Item {
            id: heroRow
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.displays.length > 1 ? "󰍺" : "󰍹"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: root.targetName !== "" ? root.targetName : "Display"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroLabel
                textFormat: Text.PlainText
                text: {
                  var summary = Model.displaySummary(root.target)
                  if (summary === "") return "No display detected"
                  return summary.toUpperCase()
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          Row {
            id: tabRow
            width: parent.width
            spacing: Style.spacing.xs

            TabButton {
              width: (tabRow.width - tabRow.spacing) / 2
              tabName: "display"
              text: "DISPLAY"
            }
            TabButton {
              width: (tabRow.width - tabRow.spacing) / 2
              tabName: "comfort"
              text: "APPEARANCE"
            }
          }

          // ---------- Display arrangement ----------
          PanelSeparator {
            id: layoutSeparator
            visible: root.activeTab === "display" && root.displays.length > 1
            foreground: root.bar.foreground
          }

          Column {
            id: layoutSection
            width: parent.width
            spacing: Style.space(8)
            visible: root.activeTab === "display" && root.displays.length > 1

            Item {
              width: parent.width
              implicitHeight: Math.max(layoutHeader.implicitHeight, layoutHint.implicitHeight)

              PanelSectionHeader {
                id: layoutHeader
                text: "DISPLAY LAYOUT"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: layoutHint
                text: "Drag to arrange · saves on drop"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MonitorArrangement {
              width: parent.width
              implicitHeight: root.arrangementHeight()
              displays: root.displays
              selectedName: root.targetName
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onPositionRequested: function(name, x, y) { root.setDisplayPosition(name, x, y) }
            }
          }

          // ---------- Brightness ----------
          PanelSeparator {
            id: brightnessSeparator
            visible: root.activeTab === "comfort" && root.brightnessAvailable
            foreground: root.bar.foreground
          }

          Column {
            id: brightnessSection
            visible: root.activeTab === "comfort" && root.brightnessAvailable
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercent.implicitHeight)

              PanelSectionHeader {
                id: brightnessHeader
                text: "BRIGHTNESS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: brightnessPercent
                textFormat: Text.PlainText
                text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: brightnessRow
              width: parent.width
              height: brightnessSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "brightness" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: brightnessSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 1
                maximum: 100
                step: 1
                value: root.brightnessPercent
                integer: true
                onMoved: function(v) { root.previewBrightness(v) }
                onReleased: function(v) {
                  brightnessDebounce.stop()
                  root.setBrightness(v)
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "brightness"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Night mode ----------
          PanelSeparator {
            id: nightSeparator
            visible: root.activeTab === "comfort"
            foreground: root.bar.foreground
          }

          Column {
            id: nightSection
            width: parent.width
            spacing: Style.space(6)
            visible: root.activeTab === "comfort"

            Item {
              width: parent.width
              implicitHeight: Math.max(nightHeader.implicitHeight,
                                      nightToggle.implicitHeight,
                                      nightTemp.implicitHeight)

              PanelSectionHeader {
                id: nightHeader
                text: "NIGHT MODE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: nightTemp
                textFormat: Text.PlainText
                text: root.nightSummary()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: nightToggle.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
              }

              ToggleSwitch {
                id: nightToggle
                checked: root.nightEnabled
                hasCursor: root.cursorActive && root.focusSection === "night" && root.selectedIndex === -1
                foreground: root.bar.foreground
                accent: Color.accent
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                onToggled: root.setNightlight(!root.nightEnabled)
                // The section's CursorSurface owns the highlight, so the
                // switch does not paint its own cursor ring on top of it.
                cursorRing: false
                onHovered: function(isHovered) {
                  if (!isHovered || root.reflowingText) return
                  root.cursorActive = true
                  root.focusSection = "night"
                  root.selectedIndex = -1
                }
              }
            }

            CursorSurface {
              id: nightRow
              width: parent.width
              height: nightSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "night" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(nightRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: nightSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                // Index over descending stops, so left is day and right is
                // night; the underlying kelvin count falls as it moves right.
                minimum: 0
                maximum: root.temperatureStops.length - 1
                step: 1
                integer: true
                tickCount: 0
                value: root.currentTemperatureIndex()
                onMoved: function(v) {
                  root.temperaturePreviewIndex = Math.round(v)
                  root.setTemperature(root.temperatureStops[Math.round(v)])
                }
                onReleased: function(v) {
                  root.temperaturePreviewIndex = Math.round(v)
                  root.setTemperature(root.temperatureStops[Math.round(v)])
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "night"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Text size ----------
          PanelSeparator {
            id: textSizeSeparator
            visible: root.activeTab === "comfort"
            foreground: root.bar.foreground
          }

          Column {
            id: textSizeSection
            width: parent.width
            spacing: Style.space(6)
            visible: root.activeTab === "comfort"

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: "TEXT SIZE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: textSizePx
                textFormat: Text.PlainText
                text: (textSizeSlider.dragging
                       ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                       : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: textSizeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "textsize"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Output geometry: resolution / refresh ----------
          PanelSeparator {
            id: resolutionSeparator
            visible: root.activeTab === "display" && root.targetEnabled
            foreground: root.bar.foreground
          }

          Column {
            id: resolutionSection
            width: parent.width
            spacing: Style.space(10)
            visible: root.activeTab === "display" && root.targetEnabled

            SearchableDropdown {
              id: resolutionDropdown
              width: parent.width
              label: "RESOLUTION"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              placeholderText: "Search resolutions..."
              emptyText: "No supported resolutions"
              options: root.targetResolutions.map(function(resolution) {
                return {
                  value: resolution.key,
                  label: resolution.label,
                  description: (resolution.current ? "Current · " : "")
                    + (resolution.preferred ? "Preferred" : "Supported mode")
                }
              })
              Binding {
                target: resolutionDropdown
                property: "value"
                value: root.currentResolutionKey()
              }
              hasCursor: root.cursorActive && root.focusSection === "resolution"
              onChanged: function(key) {
                for (var i = 0; i < root.targetResolutions.length; i++) {
                  var resolution = root.targetResolutions[i]
                  if (resolution.key === key && !resolution.current) {
                    root.setResolution(resolution)
                    break
                  }
                }
              }
              onHovered: function(isHovered) {
                if (!isHovered || root.reflowingText) return
                root.cursorActive = true
                root.focusSection = "resolution"
                root.selectedIndex = -1
              }
            }
          }

          // ---------- Refresh rate ----------
          // Only meaningful when the monitor offers more than one rate at the
          // current resolution.
          Column {
            id: refreshSection
            width: parent.width
            spacing: Style.space(10)
            visible: root.activeTab === "comfort" && root.targetEnabled && root.targetRefreshes.length > 1

            PanelSectionHeader {
              text: "REFRESH RATE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Flow {
              id: refreshRow
              width: parent.width
              spacing: Style.spacing.xs

              Repeater {
                model: root.targetRefreshes

                RefreshPill {
                  required property var modelData
                  required property int index

                  refreshInfo: modelData
                  refreshIndex: index
                }
              }
            }
          }

          // ---------- Scale ----------
          PanelSeparator {
            id: scaleSeparator
            visible: root.activeTab === "display" && root.targetEnabled
            foreground: root.bar.foreground
          }

          Column {
            id: scaleSection
            width: parent.width
            spacing: Style.space(10)
            visible: root.activeTab === "display" && root.targetEnabled

            Item {
              width: parent.width
              implicitHeight: Math.max(scaleHeader.implicitHeight, scaleValue.implicitHeight)

              PanelSectionHeader {
                id: scaleHeader
                text: "SCALE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: scaleValue
                textFormat: Text.PlainText
                text: root.currentScaleLabel()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Grid {
              id: scaleRow
              width: parent.width
              columns: root.scaleValues.length
              spacing: Style.spacing.xs

              readonly property real cellWidth: root.scaleValues.length > 0
                ? (width - spacing * (columns - 1)) / columns
                : 0

              Repeater {
                model: root.scaleValues

                ScalePill {
                  required property string modelData
                  required property int index

                  scaleValue: modelData
                  scaleIndex: index
                  width: scaleRow.cellWidth
                }
              }
            }
          }

          // ---------- Rotation ----------
          PanelSeparator {
            id: rotationSeparator
            visible: root.activeTab === "comfort" && root.targetEnabled
            foreground: root.bar.foreground
          }

          Column {
            id: rotationSection
            width: parent.width
            spacing: Style.space(10)
            visible: root.activeTab === "comfort" && root.targetEnabled

            Item {
              width: parent.width
              implicitHeight: Math.max(rotationHeader.implicitHeight, rotationValue.implicitHeight)

              PanelSectionHeader {
                id: rotationHeader
                text: "ROTATION"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: rotationValue
                textFormat: Text.PlainText
                text: root.currentRotationLabel()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Grid {
              id: rotationRow
              width: parent.width
              columns: root.rotationValues.length
              spacing: Style.spacing.xs

              readonly property real cellWidth: root.rotationValues.length > 0
                ? (width - spacing * (columns - 1)) / columns
                : 0

              Repeater {
                model: root.rotationValues

                RotationPill {
                  required property string modelData
                  required property int index

                  transformValue: modelData
                  transformIndex: index
                  width: rotationRow.cellWidth
                }
              }
            }
          }

          // ---------- Displays ----------
          PanelSeparator {
            id: displaysSeparator
            visible: root.activeTab === "comfort" && root.displays.length > 1
            foreground: root.bar.foreground
          }

          Column {
            id: displaysSection
            width: parent.width
            spacing: Style.space(10)
            visible: root.activeTab === "comfort" && root.displays.length > 1

            PanelSectionHeader {
              text: "DISPLAYS"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.displays

              MonitorRow {
                required property var modelData
                required property int index

                width: panelColumn.width
                display: modelData
                rowIndex: index
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  component TabButton: Button {
    required property string tabName

    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    active: root.activeTab === tabName

    onClicked: root.activateTab(tabName)
  }

  component RefreshPill: Button {
    id: pill
    required property var refreshInfo
    required property int refreshIndex

    text: pill.refreshInfo ? pill.refreshInfo.label : ""
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.currentRefreshIndex() === refreshIndex
    hasCursor: root.cursorActive && root.focusSection === "refresh"
      && root.selectedIndex === refreshIndex

    onClicked: if (pill.refreshInfo) root.setRefresh(pill.refreshInfo.mode)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "refresh"
      root.selectedIndex = pill.refreshIndex
    }
  }

  component ScalePill: Button {
    id: pill
    required property string scaleValue
    required property int scaleIndex

    // Show the value the compositor will actually commit. Hyprland snaps
    // fractional scales to a divisor of the mode; wlroots uses them as-is.
    text: root.effectiveScale(scaleValue) + "x"
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.activeScaleIndex() === scaleIndex || root.scalePreviewIndex === scaleIndex
    hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === scaleIndex

    onClicked: root.setScale(scaleValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "scale"
      root.selectedIndex = pill.scaleIndex
    }
  }

  component RotationPill: Button {
    id: pill
    required property string transformValue
    required property int transformIndex

    text: Model.rotationLabel(transformValue)
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.currentRotationIndex() === transformIndex
    hasCursor: root.cursorActive && root.focusSection === "rotation" && root.selectedIndex === transformIndex

    onClicked: root.setRotation(transformValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "rotation"
      root.selectedIndex = pill.transformIndex
    }
  }

  component MonitorRow: CursorSurface {
    id: monitorRow
    required property var display
    required property int rowIndex

    readonly property bool isFocused: display && display.name === root.targetName
    readonly property bool canToggle: display && (!display.enabled || root.enabledDisplayCount > 1)

    hasCursor: root.cursorActive && root.focusSection === "displays" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(monitorRow)
    current: isFocused
    foreground: root.bar.foreground
    fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
    currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)
    implicitHeight: monitorInner.implicitHeight + Style.spacing.xl
    opacity: canToggle ? 1.0 : 0.45

    Row {
      id: monitorInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: "󰍹"
        color: monitorRow.display.enabled ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.8)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(22) - Style.space(14) - Style.space(16) - parent.spacing * 3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          text: monitorRow.display.name + (monitorRow.isFocused ? " · this screen" : "")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }

        // Each row names its own mode and scale so a multi-monitor setup is
        // legible without clicking into each output.
        Text {
          textFormat: Text.PlainText
          text: Model.displaySummary(monitorRow.display)
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Text {
        textFormat: Text.PlainText
        text: monitorRow.display.enabled ? "󰄬" : ""
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        width: Style.space(14)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: monitorRow.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
        root.cursorActive = true
        root.focusSection = "displays"
        root.selectedIndex = monitorRow.rowIndex
      }
      onClicked: if (monitorRow.canToggle) root.toggleDisplay(monitorRow.display.name, monitorRow.display.enabled)
    }
  }
}
