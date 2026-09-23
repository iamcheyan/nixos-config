pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

// A small application-only launcher styled after the local dark theme.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var appLibrary: root.shell ? root.shell.appLibrary : null
  property var allApps: []
  property var filteredApps: []
  property var targetScreen: null
  property string requestedScreenName: ""
  // Lowercased Wayland app_ids of currently open toplevels, e.g.
  // { "firefox": true }. Rebuilt from ToplevelManager (works on Labwc;
  // the old hyprctl-based RunningApps.qml can never match here).
  property var runningKeys: ({})

  readonly property color launcherBackground: "#2b2b2b"
  readonly property color launcherInputBackground: "#383838"
  readonly property color launcherHover: "#3a3a3a"
  readonly property color launcherSelected: "#404040"
  readonly property color launcherBorder: "#444444"
  readonly property color launcherText: "#e0e0e0"
  readonly property color launcherTextDim: "#888888"
  readonly property color launcherTextDimmer: "#666666"
  // Quickshell already exposes each output in its compositor-scaled logical
  // coordinate space. Do not divide these dimensions by devicePixelRatio:
  // doing so makes the same launcher physically tiny on the 2x output.
  readonly property real uiScale: 1
  readonly property real iconSize: 28 * uiScale
  readonly property real rowHeight: 54 * uiScale
  readonly property real cornerRadius: 12 * uiScale
  readonly property string desktopShortcutTool:
    (Quickshell.env("QUICKSHELL_ROOT") || Quickshell.shellDir)
    + "/plugins/desktop-icons/bin/pin-application"
  readonly property var filteredAppIds: root.filteredApps.map(function(app) {
    return String(app.id)
  })

  function open(_payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(_payloadJson || "{}")) } catch (e) {}
    root.requestedScreenName = String(payload.screen || payload.screenName || "")
    root.targetScreen = root.resolveScreen(root.requestedScreenName)
    root.opened = true
    root.refreshApps()
    root.refreshRunning()
    refreshTimer.start()
    Qt.callLater(function() {
      if (panelLoader.item)
        panelLoader.item.searchFieldControl.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  function validScreen(candidate) {
    return !!(candidate && candidate.name !== undefined
      && candidate.width > 0 && candidate.height > 0)
  }

  function sameScreen(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    var ln = String(left.name || ""), rn = String(right.name || "")
    return ln !== "" && ln === rn
  }

  // Keyboard-summoned opens carry no screen name. Route them to the output
  // holding the active toplevel so Super on the secondary monitor does not
  // always land on the primary one. ToplevelManager.activeToplevel.screen
  // (singular) is unreliable on some wlroots compositors; prefer the
  // screens array like the ActiveWindow widget does.
  function focusedScreen() {
    var active = null
    try { active = ToplevelManager.activeToplevel } catch (e) { active = null }
    if (active) {
      var list = active.screens || []
      if (list.length > 0 && root.validScreen(list[0])) return list[0]
      if (active.screen && root.validScreen(active.screen)) return active.screen
    }
    return null
  }

  function resolveScreen(name) {
    var screens = Quickshell.screens || []
    if (screens.length === 0) return null
    var wanted = String(name || "")
    if (wanted) {
      var i = 0
      for (i = 0; i < screens.length; i++) {
        if (String(screens[i].name || "") === wanted) return screens[i]
      }
      // Some Qt/Wayland builds report QScreen.name differently from the
      // connector name carried in the payload. Retry case-insensitively
      // before falling back.
      var lowered = wanted.toLowerCase()
      for (i = 0; i < screens.length; i++) {
        if (String(screens[i].name || "").toLowerCase() === lowered)
          return screens[i]
      }
    } else {
      var focused = root.focusedScreen()
      if (focused) return focused
    }
    // Never return null while screens exist: a failed lookup must fall back
    // to a visible output instead of leaving the launcher silently hidden.
    // Prefer the still-valid previous target so hotplug does not jump outputs.
    if (root.validScreen(root.targetScreen)) {
      for (var j = 0; j < screens.length; j++) {
        if (root.sameScreen(screens[j], root.targetScreen)) return screens[j]
      }
    }
    var focusedFallback = root.focusedScreen()
    if (focusedFallback) return focusedFallback
    return screens[0]
  }

  function screenForName(name) {
    return root.resolveScreen(name)
  }

  function refresh() {
    root.refreshApps()
    return "ok"
  }

  function appForId(id) {
    var wanted = String(id || "")
    for (var i = 0; i < root.allApps.length; i++) {
      if (String(root.allApps[i].id || "") === wanted)
        return root.allApps[i]
    }
    return null
  }

  function appText(entry) {
    if (!entry) return ""
    return [
      root.appLibrary ? root.appLibrary.entryName(entry) : entry.name,
      root.appLibrary ? root.appLibrary.entrySubtext(entry) : "",
      entry.genericName,
      entry.comment,
      entry.id
    ].join(" ").toLowerCase()
  }

  function refreshRunning() {
    var keys = ({})
    var wins = []
    try { wins = ToplevelManager.toplevels.values || [] } catch (e) { wins = [] }
    for (var i = 0; i < wins.length; i++) {
      var w = wins[i]
      if (!w) continue
      var ids = [w.appId, w.initialAppId]
      for (var j = 0; j < ids.length; j++) {
        var key = String(ids[j] || "").toLowerCase()
        if (key) keys[key] = true
      }
    }
    root.runningKeys = keys
    // A window opened or closed while the launcher is open: re-sort so
    // running apps move to/from the top immediately.
    root.sortApps()
    root.filterApps()
  }

  // Same candidate matching the old Hyprland plugin used against
  // hyprctl classes, now checked against ToplevelManager app_ids.
  function isAppRunning(entry) {
    if (!entry) return false
    var id = String(entry.id || "").replace(/\.desktop$/i, "")
      .split("/").pop().toLowerCase()
    var rawExec = String(entry.exec || entry.command || entry.execString || "")
    var exec = rawExec.split(" ")[0].split("/").pop().toLowerCase()
    var stripped = exec.replace(/-stable$/, "").replace(/-bin$/, "")
      .replace(/^env-/, "")
    var candidates = [id, exec, stripped]
    for (var i = 0; i < candidates.length; i++)
      if (candidates[i] && root.runningKeys[candidates[i]]) return true
    for (var key in root.runningKeys) {
      if (id && (key === id || key.indexOf(id) >= 0 || id.indexOf(key) >= 0))
        return true
      if (exec && (key === exec || key.indexOf(exec) >= 0 || exec.indexOf(key) >= 0))
        return true
      if (stripped && key === stripped) return true
    }
    return false
  }

  function appSortName(entry) {
    if (!entry) return ""
    return String(root.appLibrary
      ? root.appLibrary.entryName(entry) : entry.name || entry.id).toLowerCase()
  }

  // Running apps float to the top, alphabetical within each group.
  function sortApps() {
    root.allApps.sort(function(a, b) {
      var ar = root.isAppRunning(a) ? 0 : 1
      var br = root.isAppRunning(b) ? 0 : 1
      if (ar !== br) return ar - br
      var an = root.appSortName(a), bn = root.appSortName(b)
      return an < bn ? -1 : (an > bn ? 1 : 0)
    })
  }

  function refreshApps() {
    if (!root.appLibrary) {
      root.allApps = []
      root.filteredApps = []
      return
    }

    root.appLibrary.refreshIcons()
    var entries = root.appLibrary.sortedEntries("")
    var next = []
    var seen = ({})

    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i].entry
      if (!entry || !entry.id) continue

      // Collapse the same desktop entry when it appears in multiple data
      // directories, while preserving distinct commands with the same name.
      var name = String(root.appLibrary.entryName(entry) || entry.name || entry.id)
      var icon = String(entry.icon || "")
      var command = String(entry.exec || entry.command || entry.execString || "")
      var key = [name, icon, command].join("\u001f").toLowerCase()
      if (seen[key]) continue
      seen[key] = true
      next.push(entry)
    }

    next.sort(function(a, b) {
      var an = String(root.appLibrary.entryName(a) || a.name || a.id).toLowerCase()
      var bn = String(root.appLibrary.entryName(b) || b.name || b.id).toLowerCase()
      return an < bn ? -1 : (an > bn ? 1 : 0)
    })

    root.allApps = next
    root.sortApps()
    root.filterApps()
  }

  function filterApps() {
    // Preserve keyboard position across live re-sorts (a window opening
    // while the launcher is open must not steal the current selection).
    var selectedId = ""
    if (panelLoader.item && panelLoader.item.appListControl.currentIndex >= 0
        && panelLoader.item.appListControl.currentIndex < root.filteredApps.length) {
      var selected = root.filteredApps[panelLoader.item.appListControl.currentIndex]
      if (selected) selectedId = String(selected.id || "")
    }
    var query = panelLoader.item
      ? panelLoader.item.searchFieldControl.text.trim().toLowerCase() : ""
    var next = []
    for (var i = 0; i < root.allApps.length; i++) {
      var entry = root.allApps[i]
      if (!query || root.appText(entry).indexOf(query) >= 0)
        next.push(entry)
    }
    root.filteredApps = next
    var restored = -1
    if (selectedId) {
      for (var j = 0; j < next.length; j++) {
        if (String(next[j].id || "") === selectedId) { restored = j; break }
      }
    }
    // The launcher opens without a highlighted row; keyboard navigation can still
    // select the first item with Down or Return.
    if (panelLoader.item)
      panelLoader.item.appListControl.currentIndex = restored
  }

  function launch(entry) {
    if (!entry || !root.appLibrary) return
    root.close()
    root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
  }

  function pinToDesktop(entry) {
    if (!entry || !entry.id) return
    var id = String(entry.id)
    root.close()
    Quickshell.execDetached([root.desktopShortcutTool, id])
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.refreshApps() }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.refreshRunning() }
  }

  Timer {
    id: refreshTimer
    interval: 500
    repeat: true
    property int attempts: 0

    onTriggered: {
      root.refreshApps()
      attempts += 1
      if (root.allApps.length > 0 || attempts >= 10)
        stop()
    }
    onRunningChanged: if (running) attempts = 0
  }

  Loader {
    id: panelLoader
    active: root.opened
    sourceComponent: panelComponent
  }

  Component {
    id: panelComponent

    PanelWindow {
      id: panel

      property alias searchFieldControl: searchField
      property alias appListControl: appList

      visible: root.opened
      // Bind the layer surface to the output whose bar opened the launcher,
      // falling back to the focused output and finally the primary one.
      // Never gate visibility on the lookup: a failed name match must still
      // show the launcher instead of silently staying hidden.
      screen: root.validScreen(root.targetScreen) ? root.targetScreen
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "launcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.opened
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(parent.width - 40 * root.uiScale, 620 * root.uiScale)
      height: Math.min(parent.height - 40 * root.uiScale, 480 * root.uiScale)
      radius: root.cornerRadius
      color: root.launcherBackground
      border.color: root.launcherBorder
      border.width: Math.max(0.5, root.uiScale)
      clip: true

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 62 * root.uiScale
          color: root.launcherInputBackground
          radius: root.cornerRadius

          // Only the top edge is rounded, matching the reference design.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.cornerRadius
            color: root.launcherInputBackground
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18 * root.uiScale
            anchors.rightMargin: 18 * root.uiScale
            spacing: 10 * root.uiScale

            Item {
              Layout.preferredWidth: 20 * root.uiScale
              Layout.preferredHeight: 20 * root.uiScale
              Layout.alignment: Qt.AlignVCenter

              Rectangle {
                x: 2 * root.uiScale
                y: 2 * root.uiScale
                width: 11 * root.uiScale
                height: 11 * root.uiScale
                radius: width / 2
                color: "transparent"
                border.color: root.launcherTextDim
                border.width: Math.max(0.75, root.uiScale)
              }

              Rectangle {
                x: 12 * root.uiScale
                y: 13 * root.uiScale
                width: 7 * root.uiScale
                height: Math.max(0.75, root.uiScale)
                color: root.launcherTextDim
                rotation: 45
                transformOrigin: Item.Left
              }
            }

            TextInput {
              id: searchField
              Layout.fillWidth: true
              Layout.fillHeight: true
              color: root.launcherText
              selectionColor: root.launcherSelected
              selectedTextColor: root.launcherText
              font.family: "Noto Sans CJK JP"
              font.pixelSize: 15 * root.uiScale
              verticalAlignment: TextInput.AlignVCenter
              clip: true
              focus: root.opened
              onTextChanged: root.filterApps()

              Keys.onEscapePressed: root.close()
              Keys.onReturnPressed: {
                var entry = appList.currentIndex >= 0
                  ? root.filteredApps[appList.currentIndex]
                  : root.filteredApps.length > 0 ? root.filteredApps[0] : null
                if (entry) root.launch(entry)
              }
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) {
                  appList.incrementCurrentIndex()
                  event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  appList.decrementCurrentIndex()
                  event.accepted = true
                }
              }

              Text {
                anchors.fill: parent
                visible: !parent.text
                text: "Search for apps and commands..."
                color: root.launcherTextDim
                font: parent.font
                verticalAlignment: Text.AlignVCenter
              }
            }

          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(0.5, root.uiScale)
            color: root.launcherBorder
            z: 2
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true

          ListView {
            id: appList
            anchors.fill: parent
            anchors.topMargin: 6 * root.uiScale
            anchors.bottomMargin: 6 * root.uiScale
            anchors.leftMargin: 8 * root.uiScale
            anchors.rightMargin: 8 * root.uiScale
            model: root.filteredAppIds
            currentIndex: -1
            spacing: 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: false

            delegate: Item {
              id: appItem
              required property string modelData
              required property int index
              readonly property var app: root.appForId(modelData)
              readonly property bool isRunning: root.isAppRunning(app)
              width: appList.width
              height: root.rowHeight

              Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 0
                anchors.rightMargin: 0
                anchors.topMargin: 2 * root.uiScale
                anchors.bottomMargin: 2 * root.uiScale
                radius: 8 * root.uiScale
                color: mouse.containsMouse || appList.currentIndex === index
                  ? (appList.currentIndex === index
                    ? root.launcherSelected : root.launcherHover)
                  : "transparent"
              }

              // Running marker: yellow dot left of the icon, same #f5c542
              // the old grid-layout plugin used under its labels.
              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 7 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                width: 6 * root.uiScale
                height: 6 * root.uiScale
                radius: width / 2
                color: "#f5c542"
                visible: appItem.isRunning
                z: 2
              }

              Image {
                id: appIcon
                anchors.left: parent.left
                anchors.leftMargin: 18 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                width: root.iconSize
                height: root.iconSize
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * (panel.screen
                  ? panel.screen.devicePixelRatio : Screen.devicePixelRatio)
                sourceSize.height: height * (panel.screen
                  ? panel.screen.devicePixelRatio : Screen.devicePixelRatio)
                asynchronous: true
                mipmap: true
                source: root.appLibrary && app && app.icon
                  ? root.appLibrary.iconSource(app.icon) : ""
              }

              Rectangle {
                anchors.left: appIcon.left
                anchors.top: appIcon.top
                width: appIcon.width
                height: appIcon.height
                radius: 6
                visible: !app || !app.icon || appIcon.status !== Image.Ready
                color: root.launcherSelected
                border.color: root.launcherBorder
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: {
                    var name = root.appLibrary
                      ? root.appLibrary.entryName(app)
                      : String(app ? app.name || app.id : "?")
                    return name.length > 0 ? name.charAt(0).toUpperCase() : "?"
                  }
                  color: root.launcherText
                  font.family: "Noto Sans CJK JP"
                  font.pixelSize: 16 * root.uiScale
                }
              }

              Text {
                anchors.left: appIcon.right
                anchors.leftMargin: 12 * root.uiScale
                anchors.right: parent.right
                anchors.rightMargin: root.appLibrary && app
                  && root.appLibrary.entrySubtext(app).length > 0
                  ? 190 * root.uiScale : 52 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                text: root.appLibrary && app
                  ? root.appLibrary.entryName(app) : ""
                color: root.launcherText
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 13 * root.uiScale
                elide: Text.ElideRight
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: 52 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                text: root.appLibrary && app
                  ? root.appLibrary.entrySubtext(app) : ""
                color: root.launcherTextDim
                font.family: "Noto Sans CJK JP"
                font.pixelSize: 11 * root.uiScale
                visible: text.length > 0
                elide: Text.ElideLeft
                width: Math.min(160 * root.uiScale, implicitWidth)
              }

              Rectangle {
                id: desktopButton
                z: 2
                anchors.right: parent.right
                anchors.rightMargin: 14 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                width: 20 * root.uiScale
                height: 20 * root.uiScale
                radius: 4 * root.uiScale
                color: desktopButtonMouse.containsMouse
                  ? root.launcherSelected : "transparent"
                visible: desktopButtonMouse.containsMouse
                  || appList.currentIndex === index

                Text {
                  anchors.centerIn: parent
                  text: "⇲"
                  color: desktopButtonMouse.containsMouse
                    ? root.launcherText : root.launcherTextDim
                  font.family: "Noto Sans CJK JP"
                  font.pixelSize: 16 * root.uiScale
                }

                MouseArea {
                  id: desktopButtonMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    mouse.accepted = true
                    root.pinToDesktop(app)
                  }
                }
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: appList.currentIndex = index
                onClicked: if (app) root.launch(app)
              }
            }
          }

          Rectangle {
            id: scrollTrack
            anchors.top: appList.top
            anchors.bottom: appList.bottom
            anchors.right: parent.right
            width: 4 * root.uiScale
            radius: 2
            color: root.launcherTextDimmer
            visible: appList.contentHeight > appList.height

            readonly property real thumbHeight: Math.max(32 * root.uiScale,
              height * appList.visibleArea.heightRatio)

            function scrollFromPointer(pointerY) {
              var maxThumbY = Math.max(0, height - thumbHeight)
              var thumbY = Math.max(0, Math.min(maxThumbY,
                pointerY - thumbHeight / 2))
              var maxContentY = Math.max(0,
                appList.contentHeight - appList.height)
              appList.contentY = maxThumbY > 0
                ? maxContentY * thumbY / maxThumbY : 0
            }

            Rectangle {
              x: 0
              width: parent.width
              height: scrollTrack.thumbHeight
              y: (parent.height - height) * appList.visibleArea.yPosition
              radius: 2
              color: root.launcherTextDim
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              cursorShape: Qt.SizeVerCursor
              onPressed: function(mouse) {
                scrollTrack.scrollFromPointer(mouse.y)
                mouse.accepted = true
              }
              onPositionChanged: function(mouse) {
                if (mouse.buttons & Qt.LeftButton)
                  scrollTrack.scrollFromPointer(mouse.y)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.filteredApps.length === 0
            text: root.allApps.length === 0
              ? "No applications found" : "No matching applications"
            color: root.launcherTextDim
            font.family: "Noto Sans CJK JP"
            font.pixelSize: 13 * root.uiScale
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      z: -1
      onClicked: root.close()
    }
    }
  }
}
