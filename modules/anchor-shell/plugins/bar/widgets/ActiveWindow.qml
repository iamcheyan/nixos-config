import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.active-window"

  // A Bar instance is created once per monitor. Do not use the global
  // ToplevelManager.activeToplevel here: on Labwc that only describes the
  // keyboard-focused monitor and makes every bar show the same title.
  readonly property var barScreen: (root.QsWindow && root.QsWindow.window && root.QsWindow.window.screen)
    ? root.QsWindow.window.screen
    : (Window.window && Window.window.screen ? Window.window.screen : (Quickshell.screens.length === 1 ? Quickshell.screens[0] : null))
  readonly property var appLibrary: bar && bar.shell ? bar.shell.appLibrary : null
  property int toplevelSerial: 0

  function isVisibleOnBarScreen(window) {
    if (!window) return false
    if (!barScreen) return window === ToplevelManager.activeToplevel
    var screens = window.screens || []
    // Some wlroots foreign-toplevel implementations do not populate the
    // screens property. In that case retain the global active window rather
    // than filtering every window out and hiding the widget entirely.
    if (screens.length === 0) return window === ToplevelManager.activeToplevel
    for (var i = 0; i < screens.length; i++) {
      if (screens[i] === barScreen || String(screens[i].name || "") === String(barScreen.name || ""))
        return true
    }
    return false
  }

  function windowForBarScreen() {
    var serial = root.toplevelSerial
    var windows = ToplevelManager.toplevels.values || []
    var fallback = null
    for (var i = 0; i < windows.length; i++) {
      var window = windows[i]
      if (!root.isVisibleOnBarScreen(window) || window.minimized) continue
      // Labwc exposes the windows on the current output/workspace through
      // foreign-toplevel-management. Prefer its activated window, while the
      // fallback keeps the other monitor useful when focus is elsewhere.
      if (window.activated) return window
      if (!fallback) fallback = window
    }
    return fallback
  }

  function iconForToplevel(window) {
    if (!window || !appLibrary) return ""
    var appId = String(window.appId || window.initialAppId || "")
    if (!appId) return ""

    // The Wayland app_id is not required to equal the desktop-file ID. Use
    // Quickshell's desktop-entry heuristics first, then the indexed fallback
    // used by the launcher so Firefox/terminal variants resolve correctly.
    var entry = DesktopEntries.heuristicLookup(appId)
    if (!entry) entry = DesktopEntries.byId(appId)
    if (entry && entry.icon) return appLibrary.iconSource(entry.icon)

    var normalized = appId.toLowerCase().replace(/\.desktop$/, "")
    var entries = DesktopEntries.applications.values || []
    for (var i = 0; i < entries.length; i++) {
      var candidate = entries[i]
      var entryId = String(candidate.id || "").toLowerCase().replace(/\.desktop$/, "")
      var startupClass = String(candidate.startupClass || "").toLowerCase()
      if (entryId === normalized || startupClass === normalized)
        return appLibrary.iconSource(candidate.icon)
    }

    var parts = appId.split(".")
    return appLibrary.iconSource(parts[parts.length - 1] || appId)
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.toplevelSerial++ }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.toplevelSerial++ }
  }

  readonly property var toplevel: windowForBarScreen()
  readonly property string title: toplevel ? (toplevel.title || toplevel.appId || "") : ""
  readonly property string iconSource: iconForToplevel(toplevel)
  readonly property int maxLabelWidth: Number(setting("maxWidth", 280))

  visible: title !== "" && !vertical
  implicitWidth: visible ? Math.min(maxLabelWidth, labelText.implicitWidth) + Style.spacing.controlPaddingX * 2 : 0
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    clip: true

    Text {
      id: labelText
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: appIcon.visible ? appIcon.right : parent.left
      anchors.leftMargin: appIcon.visible ? Style.space(6) : 0
      width: parent.width - (appIcon.visible ? appIcon.width + Style.space(6) : 0)
      text: root.title
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
      elide: Text.ElideRight
      opacity: 0.85
    }

    Image {
      id: appIcon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.font.body
      height: width
      source: root.iconSource
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      fillMode: Image.PreserveAspectFit
      smooth: true
      visible: root.iconSource !== ""
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (!root.toplevel) return
      if (mouse.button === Qt.MiddleButton) {
        root.toplevel.close()
      } else if (mouse.button === Qt.RightButton) {
        root.toplevel.close()
      } else {
        root.toplevel.activate()
      }
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.title)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
