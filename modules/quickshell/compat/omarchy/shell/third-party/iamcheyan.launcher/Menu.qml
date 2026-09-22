pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel

// The launcher surface follows the original Sumika launcher: a rounded card,
// a top-right search field, and an icon grid. Application discovery and launch
// are still delegated to Omarchy's native AppLibrary.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property var allApps: []
  property var filteredApps: []
  property var appLibrary: root.shell ? root.shell.appLibrary : null
  property var nativeDefaults: ({})
  property var nativeOverrides: ({})
  property string activeSection: "apps"
  property string activeSectionLabel: "Applications"
  property var allSectionRows: []
  property var sectionRows: []
  // GridView delegates receive primitive IDs only. Passing the JavaScript
  // object arrays directly as modelData makes Qt 6.11 enter its QVariantMap
  // conversion path while a delegate is being incubated; that path is where
  // the recorded SIGSEGV occurs during a shell/output reload.
  readonly property var filteredAppIds: root.filteredApps.map(function(app) { return String(app.id) })
  readonly property var sectionRowIds: root.sectionRows.map(function(row) { return String(row.id) })
  readonly property var globalSearchRowIds: root.searchRows().map(function(row, index) {
    return String(row.kind || "row") + ":" + String(row.kind === "app" ? row.entry.id : row.id) + ":" + String(index)
  })
  readonly property var navigationIds: ["apps", "learn", "trigger", "style", "setup", "install", "remove", "update", "about", "system"]
  property bool globalSearchActive: false
  property var globalSearchRows: []
  property var searchNavigationIds: ["all"]
  property string searchCategoryFilter: "all"
  property int searchSelection: -1
  property bool rebuildingSection: false
  property bool escapeNeedsSecondPress: false
  readonly property string defaultMenuPath: root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  readonly property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var pinnedIds: ({})
  property var runningSet: ({})
  property bool pinnedIdsLoaded: false
  readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/iamcheyan-launcher/pinned-apps"
  property int layoutColumns: 8
  property int layoutRows: 4
  property int layoutIconSize: 48
  property int layoutFontSize: 14
  readonly property string layoutStateFile: Quickshell.env("HOME") + "/.local/state/iamcheyan-launcher/layout.json"
  readonly property real layoutCellWidth: Math.max(
    140,
    root.layoutIconSize + Math.max(48, root.layoutFontSize * 3.5) + 32)
  readonly property real layoutRowGap: Math.max(16, root.layoutFontSize * 1.5)
  readonly property real layoutCellHeight: Math.max(
    128,
    root.layoutIconSize + Math.max(52, root.layoutFontSize * 3.5) + 24)
  readonly property real automaticCardWidth: Math.min(panel.width * 0.80, 1260)
  readonly property int automaticGridRows: 4
  readonly property real automaticCardHeight: Math.min(panel.height - 40,
    72 + root.automaticGridRows * 128 + 98)
  readonly property real configuredCardWidth: Math.min(panel.width - 40,
    Math.max(400, root.layoutColumns * root.layoutCellWidth + 40))
  readonly property real configuredCardHeight: Math.min(panel.height - 40,
    Math.max(360, root.layoutRows * root.layoutCellHeight + 170))

  function open(payloadJson) {
    root.opened = true
    root.escapeNeedsSecondPress = false
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (error) {}
    root.selectSection(String(payload.menu || "apps"), false)
    pinnedFile.reload()
    runningAppsLoader.active = true
    if (runningAppsLoader.item) runningAppsLoader.item.refresh()
    root.refreshApps()
    appRefreshTimer.restart()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.escapeNeedsSecondPress = false
    runningAppsLoader.active = false
    root.runningSet = ({})
  }

  function refresh() {
    root.refreshApps()
    root.selectSection(root.activeSection, false)
    return "ok"
  }

  function navigationItems() {
    var ids = ["apps", "learn", "trigger", "style", "setup", "install", "remove", "update", "about", "system"]
    var items = MenuModel.merge(root.nativeDefaults, root.nativeOverrides)
    var result = []
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      var item = items[id] || ({})
      result.push({
        id: id,
        label: id === "apps" ? "Applications" : String(item.label || id),
        icon: String(item.icon || "")
      })
    }
    return result
  }

  function navigationActive(id) {
    if (root.globalSearchActive) return id === root.searchCategoryFilter
    return root.activeSection === id || root.activeSection.indexOf(id + ".") === 0
  }

  function scrollThumbY(view, trackHeight, thumbHeight) {
    var contentRange = Math.max(0, view.contentHeight - view.height)
    var trackRange = Math.max(0, trackHeight - thumbHeight)
    if (contentRange <= 0 || trackRange <= 0) return 0
    return Math.max(0, Math.min(trackRange,
      (view.contentY / contentRange) * trackRange))
  }

  function selectSection(id, focusSearch) {
    var items = MenuModel.merge(root.nativeDefaults, root.nativeOverrides)
    if (id === "apps" || !items[id]) {
      root.activeSection = "apps"
      root.activeSectionLabel = "Applications"
      root.sectionRows = []
      root.refreshApps()
      if (focusSearch) Qt.callLater(function() { searchField.forceActiveFocus() })
      return
    }

    var current = items[id] || ({})
    if (current.action && !MenuModel.isParent(id, items)) {
      // A navigation item with only one direct action must still open a
      // submenu. Executing it on hover makes the bottom navigation unsafe.
      root.activeSection = id
      root.activeSectionLabel = String(current.label || id)
      root.allSectionRows = [{
        id: id,
        label: String(current.label || id),
        icon: String(current.icon || ""),
        description: String(current.description || ""),
        action: String(current.action || ""),
        hasChildren: false
      }]
      root.filterCurrentSection()
      if (focusSearch) Qt.callLater(function() { sectionGrid.forceActiveFocus() })
      return
    }

    root.activeSection = id
    root.activeSectionLabel = String(current.label || id)
    var rows = []
    for (var key in items) {
      if (MenuModel.parentId(key) !== id) continue
      var item = items[key] || ({})
      rows.push({
        id: key,
        label: String(item.label || key),
        icon: String(item.icon || ""),
        description: String(item.description || ""),
        action: String(item.action || ""),
        hasChildren: MenuModel.isParent(key, items)
      })
    }
    if (MenuModel.parentId(id) !== "root") {
      rows.unshift({
        id: "__back__",
        label: "Back",
        icon: "",
        description: "",
        action: "",
        hasChildren: false
      })
    }
    root.allSectionRows = rows
    root.filterCurrentSection()
    if (focusSearch) Qt.callLater(function() { sectionGrid.forceActiveFocus() })
  }

  function activateSectionRow(row) {
    if (!row) return
    if (row.id === "__back__") {
      root.selectSection(MenuModel.parentId(root.activeSection), true)
      return
    }
    if (row.hasChildren) root.selectSection(row.id, true)
    else if (row.action) {
      Util.execDetached(row.action)
      root.close()
    }
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
      var displayName = String(root.appLibrary.entryName(entry) || entry.name || entry.id)
      var iconName = String(entry.icon || "")
      // AppLibrary can expose the same desktop entry from both the user and
      // system application directories. Keep distinct commands, but collapse
      // identical name/icon/command entries into one launcher item.
      var command = String(entry.exec || entry.command || entry.execString || "")
      var key = [displayName, iconName, command].join("\u001f").toLowerCase()
      if (seen[key]) continue
      seen[key] = true
      next.push(entry)
    }
    root.allApps = next
    root.filterApps()
  }

  function appForId(id) {
    var wanted = String(id || "")
    for (var i = 0; i < root.allApps.length; i++) {
      if (String(root.allApps[i].id || "") === wanted) return root.allApps[i]
    }
    return null
  }

  function sectionRowForId(id) {
    var wanted = String(id || "")
    for (var i = 0; i < root.sectionRows.length; i++) {
      if (String(root.sectionRows[i].id || "") === wanted) return root.sectionRows[i]
    }
    return null
  }

  function globalSearchRowForId(id) {
    var wanted = String(id || "")
    var rows = root.searchRows()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var key = String(row.kind || "row") + ":" + String(row.kind === "app" ? row.entry.id : row.id) + ":" + String(i)
      if (key === wanted) return row
    }
    return null
  }

  function navigationItemForId(id) {
    if (id === "all") return { id: "all", label: "All", icon: "" }
    var items = MenuModel.merge(root.nativeDefaults, root.nativeOverrides)
    var item = items[String(id || "")] || ({})
    return {
      id: String(id || ""),
      label: id === "apps" ? "Applications" : String(item.label || id),
      icon: String(item.icon || "")
    }
  }

  function filterApps() {
    var query = searchField.text.trim().toLowerCase()
    var next = []
    for (var i = 0; i < root.allApps.length; i++) {
      var entry = root.allApps[i]
      var text = [
        root.appLibrary ? root.appLibrary.entryName(entry) : entry.name,
        root.appLibrary ? root.appLibrary.entrySubtext(entry) : "",
        entry.id,
        entry.genericName,
        entry.comment
      ].join(" ").toLowerCase()
      if (!query || text.indexOf(query) >= 0) next.push(entry)
    }
    next.sort(function(a, b) {
      var ap = root.pinnedIds[a.id] ? 1 : 0
      var bp = root.pinnedIds[b.id] ? 1 : 0
      if (ap !== bp) return bp - ap
      var an = String(root.appLibrary ? root.appLibrary.entryName(a) : a.name).toLowerCase()
      var bn = String(root.appLibrary ? root.appLibrary.entryName(b) : b.name).toLowerCase()
      return an < bn ? -1 : (an > bn ? 1 : 0)
    })
    root.filteredApps = next
  }

  function filterCurrentSection() {
    var query = searchField.text.trim().toLowerCase()
    root.globalSearchActive = query.length > 0
    if (root.globalSearchActive) {
      root.filterGlobalSearch(query)
      return
    }
    root.searchCategoryFilter = "all"
    root.searchNavigationIds = ["all"]
    root.searchSelection = -1
    if (root.activeSection === "apps") {
      root.filterApps()
      return
    }
    if (!query) {
      if (!root.rebuildingSection) {
        root.rebuildingSection = true
        root.selectSection(root.activeSection, false)
        root.rebuildingSection = false
      } else {
        root.sectionRows = root.allSectionRows
      }
      return
    }
    root.sectionRows = root.allSectionRows.filter(function(row) {
      return (row.label + " " + row.description).toLowerCase().indexOf(query) >= 0
    })
  }

  function filterGlobalSearch(query) {
    var rows = []
    var normalized = String(query || "").toLowerCase()
    var menuRows = MenuModel.flatten(root.nativeDefaults, root.nativeOverrides)

    for (var i = 0; i < root.allApps.length; i++) {
      var app = root.allApps[i]
      var appLabel = String(root.appLibrary ? root.appLibrary.entryName(app) : app.name || app.id)
      var appText = [appLabel, app.genericName, app.comment, app.id].join(" ").toLowerCase()
      if (appText.indexOf(normalized) < 0) continue
      rows.push({
        kind: "app",
        entry: app,
        label: appLabel,
        secondary: "Applications",
        icon: String(app.icon || ""),
        running: root.isAppRunning(app)
      })
    }

    for (var j = 0; j < menuRows.length; j++) {
      var menuRow = menuRows[j]
      var menuText = [menuRow.label, menuRow.description, menuRow.path, menuRow.id].join(" ").toLowerCase()
      if (menuText.indexOf(normalized) < 0) continue
      rows.push({
        kind: "action",
        id: menuRow.id,
        label: menuRow.label,
        secondary: menuRow.path || "Menu",
        description: menuRow.description,
        icon: menuRow.icon,
        action: menuRow.action
      })
    }

    rows.sort(function(a, b) {
      // Keep application matches at the front so the most common search
      // target is always the first result group.
      var ak = a.kind === "app" ? 0 : 1
      var bk = b.kind === "app" ? 0 : 1
      if (ak !== bk) return ak - bk
      var al = String(a.label).toLowerCase()
      var bl = String(b.label).toLowerCase()
      return al < bl ? -1 : (al > bl ? 1 : String(a.secondary).localeCompare(String(b.secondary)))
    })
    root.globalSearchRows = rows
    root.searchCategoryFilter = "all"
    var categoryIds = ["all"]
    var seenCategories = ({ all: true })
    for (var k = 0; k < rows.length; k++) {
      var categoryId = root.searchCategoryId(rows[k])
      if (categoryId && !seenCategories[categoryId]) {
        seenCategories[categoryId] = true
        categoryIds.push(categoryId)
      }
    }
    root.searchNavigationIds = categoryIds
    root.searchSelection = rows.length > 0 ? 0 : -1
    root.updateSearchCategory()
  }

  function searchRows() {
    if (root.searchCategoryFilter === "all") return root.globalSearchRows
    return root.globalSearchRows.filter(function(row) {
      return root.searchCategoryId(row) === root.searchCategoryFilter
    })
  }

  function selectSearchCategory(id) {
    root.searchCategoryFilter = id || "all"
    var rows = root.searchRows()
    root.searchSelection = rows.length > 0 ? 0 : -1
    if (root.searchCategoryFilter !== "all") {
      root.activeSection = root.searchCategoryFilter
      root.activeSectionLabel = root.searchCategoryFilter === "apps"
        ? "Applications"
        : String(root.navigationItemForId(root.searchCategoryFilter).label
          || root.searchCategoryFilter)
    }
    Qt.callLater(function() {
      if (searchGrid && rows.length > 0) searchGrid.positionViewAtIndex(0, GridView.Beginning)
    })
  }

  function moveSearchSelection(delta) {
    var rows = root.searchRows()
    if (!root.globalSearchActive || rows.length === 0) return
    var current = root.searchSelection < 0 ? 0 : root.searchSelection
    var next = Math.max(0, Math.min(
      rows.length - 1, current + delta))
    root.searchSelection = next
    root.updateSearchCategory()
    Qt.callLater(function() {
      if (searchGrid) searchGrid.positionViewAtIndex(next, GridView.Contain)
    })
  }

  function activateSelectedSearchRow() {
    if (!root.globalSearchActive || root.searchSelection < 0) return false
    var row = root.searchRows()[root.searchSelection]
    if (!row) return false
    root.activateGlobalSearchRow(row)
    return true
  }

  function searchCategoryId(row) {
    if (!row || row.kind === "app") return "apps"
    var id = String(row.id || "")
    var dot = id.indexOf(".")
    return dot >= 0 ? id.slice(0, dot) : id
  }

  function updateSearchCategory() {
    if (!root.globalSearchActive || root.searchSelection < 0) return
    var row = root.searchRows()[root.searchSelection]
    var categoryId = root.searchCategoryId(row)
    if (!categoryId) return
    root.activeSection = categoryId
    root.activeSectionLabel = categoryId === "apps"
      ? "Applications"
      : String(root.navigationItemForId(categoryId).label || categoryId)
  }

  function activateGlobalSearchRow(row) {
    if (!row) return
    if (row.kind === "app") root.launch(row.entry)
    else if (row.action) {
      Util.execDetached(row.action)
      root.close()
    }
  }

  function samePinnedIds(a, b) {
    var ak = Object.keys(a || {}).filter(function(k) { return a[k] }).sort()
    var bk = Object.keys(b || {}).filter(function(k) { return b[k] }).sort()
    if (ak.length !== bk.length) return false
    for (var i = 0; i < ak.length; i++) if (ak[i] !== bk[i]) return false
    return true
  }

  function savePinnedIds() {
    var ids = []
    for (var id in root.pinnedIds) if (root.pinnedIds[id]) ids.push(id)
    ids.sort()
    var payload = ids.join("\\n") + (ids.length ? "\\n" : "")
    Util.execDetached("mkdir -p " + Util.shellQuote(Quickshell.env("HOME") + "/.local/state/iamcheyan-launcher")
      + " && printf %s " + Util.shellQuote(payload) + " > " + Util.shellQuote(root.stateFile))
  }

  function togglePinned(id) {
    var next = Object.assign({}, root.pinnedIds)
    if (next[id]) delete next[id]
    else next[id] = true
    root.pinnedIds = next
    root.savePinnedIds()
    root.filterApps()
  }

  function boundedLayoutValue(value, fallback, minimum, maximum) {
    var number = parseInt(value, 10)
    if (isNaN(number)) return fallback
    return Math.max(minimum, Math.min(maximum, number))
  }

  function isAppRunning(app) {
    if (!app) return false
    var id = String(app.id || "").replace(/\\.desktop$/i, "").split("/").pop().toLowerCase()
    var exec = String(app.execString || "").split(" ")[0].split("/").pop().toLowerCase()
    var stripped = exec.replace(/-stable$/, "").replace(/-bin$/, "").replace(/^env-/, "")
    var candidates = [id, exec, stripped]
    for (var i = 0; i < candidates.length; i++) if (candidates[i] && root.runningSet[candidates[i]]) return true
    for (var key in root.runningSet) {
      if (id && (key === id || key.indexOf(id) >= 0 || id.indexOf(key) >= 0)) return true
      if (exec && (key === exec || key.indexOf(exec) >= 0 || exec.indexOf(key) >= 0)) return true
      if (stripped && key === stripped) return true
    }
    return false
  }

  function launch(entry) {
    if (!entry || !root.appLibrary) return
    root.close()
    root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.refreshApps() }
  }

  Timer {
    id: appRefreshTimer
    interval: 500
    repeat: true
    property int attempts: 0
    onTriggered: {
      root.refreshApps()
      attempts += 1
      if (root.allApps.length > 1 || attempts >= 10) stop()
    }
    onRunningChanged: if (running) attempts = 0
  }

  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.nativeDefaults = MenuModel.parse(text())
      root.selectSection(root.activeSection, false)
    }
    onFileChanged: reload()
  }

  FileView {
    id: layoutStateFileView
    path: root.layoutStateFile
    printErrors: false
    watchChanges: true
    onLoaded: {
      try {
        var saved = JSON.parse(text())
        root.layoutColumns = boundedLayoutValue(saved.columns, 0, 1, 20)
        root.layoutRows = boundedLayoutValue(saved.rows, 0, 1, 10)
        root.layoutIconSize = boundedLayoutValue(saved.iconSize, 52, 24, 96)
        root.layoutFontSize = boundedLayoutValue(saved.fontSize, 14, 10, 24)
      } catch (error) {
        root.layoutColumns = 8
        root.layoutRows = 4
        root.layoutIconSize = 48
        root.layoutFontSize = 14
      }
    }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.nativeOverrides = MenuModel.parse(text())
      root.selectSection(root.activeSection, false)
    }
    onLoadFailed: {
      root.nativeOverrides = ({})
      root.selectSection(root.activeSection, false)
    }
    onFileChanged: reload()
  }

  FileView {
    id: pinnedFile
    path: root.stateFile
    printErrors: false
    onLoaded: {
      var next = ({})
      var lines = text().split("\\n")
      for (var i = 0; i < lines.length; i++) {
        var id = lines[i].trim()
        if (id) next[id] = true
      }
      root.pinnedIdsLoaded = true
      if (!root.samePinnedIds(root.pinnedIds, next)) root.pinnedIds = next
      root.filterApps()
    }
    onLoadFailed: {
      root.pinnedIdsLoaded = true
      root.filterApps()
    }
  }

  Loader {
    id: runningAppsLoader
    active: false
    asynchronous: true
    source: "RunningApps.qml"
    visible: false
    onLoaded: root.runningSet = item.runningSet
  }

  Connections {
    target: runningAppsLoader.item
    enabled: runningAppsLoader.item !== null
    function onRunningSetChanged() { root.runningSet = runningAppsLoader.item.runningSet }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "iamcheyan-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
      id: card
      width: root.layoutColumns > 0 ? root.configuredCardWidth : root.automaticCardWidth
      height: root.layoutRows > 0 ? root.configuredCardHeight : root.automaticCardHeight
      anchors.centerIn: parent
      color: Color.menu.background
      radius: 18
      border.color: Color.accent
      border.width: 1
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 72

          Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 26
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340
            height: 32
            radius: 16
            color: Color.menu.selectedBackground
            border.width: 0

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 7

              Text {
                text: "/"
                color: Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: root.layoutFontSize
                  font.weight: Font.DemiBold
              }

              TextInput {
                id: searchField
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Color.menu.text
                selectionColor: "#6c8cff"
                selectedTextColor: "#101010"
                font.family: Style.font.menuFamily
                font.pixelSize: root.layoutFontSize
                  font.weight: Font.DemiBold
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                onTextChanged: {
                  var wasGlobalSearch = root.globalSearchActive
                  if (text.length > 0) root.escapeNeedsSecondPress = false
                  root.filterCurrentSection()
                  // Clearing a global search must return to the application
                  // page instead of leaving an empty menu category selected.
                  if (!text.trim() && wasGlobalSearch)
                    root.selectSection("apps", false)
                }
                Keys.onEscapePressed: {
                  if (!root.escapeNeedsSecondPress
                      && (searchField.text.length > 0 || searchField.activeFocus)) {
                    searchField.clear()
                    root.escapeNeedsSecondPress = true
                  } else {
                    root.close()
                  }
                }
                Keys.onReturnPressed: {
                  if (!root.activateSelectedSearchRow()
                      && root.filteredApps.length > 0)
                    root.launch(root.filteredApps[0])
                }
                Keys.onPressed: function(event) {
                  if (!root.globalSearchActive) return
                  if (event.key === Qt.Key_Left) {
                    root.moveSearchSelection(-1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Right) {
                    root.moveSearchSelection(1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    root.moveSearchSelection(-searchGrid.columnCount)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    root.moveSearchSelection(searchGrid.columnCount)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Backtab
                      || (event.key === Qt.Key_Tab
                          && (event.modifiers & Qt.ShiftModifier))) {
                    root.moveSearchSelection(-1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Tab) {
                    root.moveSearchSelection(1)
                    event.accepted = true
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !parent.text
                  text: "Type to search apps..."
                  color: Color.muted
                  font: parent.font
                }
              }

              Text {
                Layout.preferredWidth: 24
                Layout.fillHeight: true
                text: "×"
                visible: searchField.text.length > 0
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: root.layoutFontSize + 4
                  font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: searchField.clear()
                }
              }
            }
          }

        }

        Item {
          visible: root.globalSearchActive
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.leftMargin: 12
          Layout.rightMargin: 12
          Layout.topMargin: 0
          Layout.bottomMargin: 0
          clip: true

          GridView {
            id: searchGrid
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            property int columnCount: root.layoutColumns > 0
              ? root.layoutColumns
              : Math.max(1, Math.floor(width / root.layoutCellWidth))
            width: root.layoutColumns > 0
              ? Math.min(parent.width - 16, root.layoutColumns * root.layoutCellWidth)
              : parent.width - 16
            cellWidth: width / columnCount
            cellHeight: root.layoutRows > 0 ? root.layoutCellHeight : 128
            height: Math.floor(parent.height / cellHeight) * cellHeight
            snapMode: GridView.SnapToRow
            model: root.globalSearchRowIds
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 2800

            delegate: Item {
              id: searchItem
              required property string modelData
              required property int index
              readonly property var row: root.globalSearchRowForId(modelData)
              width: searchGrid.cellWidth
              height: searchGrid.cellHeight
              property bool isApp: row ? row.kind === "app" : false

              Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) - 6
                height: width
                radius: width / 2
                color: searchMouse.containsMouse || index === root.searchSelection
                  ? Color.menu.selectedBackground : "transparent"
              }

              Item {
                id: searchIconBox
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 12
                width: Math.min(root.layoutIconSize, Math.max(1, parent.width - 10))
                height: width

                Image {
                  id: searchAppIcon
                  anchors.fill: parent
                  visible: searchItem.isApp
                  fillMode: Image.PreserveAspectFit
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  asynchronous: true
                  mipmap: true
                  source: searchItem.isApp && root.appLibrary && row.entry.icon
                    ? root.appLibrary.iconSource(row.entry.icon)
                    : ""
                }

                Rectangle {
                  anchors.fill: parent
                  visible: searchItem.isApp && (!row.entry.icon
                    || searchAppIcon.status !== Image.Ready || searchAppIcon.source === "")
                  radius: width / 2
                  color: Color.menu.selectedBackground
                  border.color: Color.menu.border
                  border.width: 1

                  Text {
                    anchors.centerIn: parent
                    text: row && row.label.length > 0 ? row.label.charAt(0).toUpperCase() : "?"
                    color: Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: root.layoutFontSize + 11
                  font.weight: Font.DemiBold
                  }
                }

                Text {
                  anchors.fill: parent
                  visible: !searchItem.isApp
                  text: row ? (row.icon || "□") : "□"
                  color: Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.layoutFontSize + 20
                  font.weight: Font.DemiBold
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
              }

              Text {
                anchors.top: searchIconBox.bottom
                anchors.topMargin: 8
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 5
                anchors.rightMargin: 5
                height: Math.max(36, root.layoutFontSize * 2.4)
                text: row ? row.label : ""
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: root.layoutFontSize
                  font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }

              Text {
                anchors.top: searchIconBox.bottom
                anchors.topMargin: 29
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 5
                anchors.rightMargin: 5
                height: 36
                text: row ? row.secondary : ""
                color: Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: Math.max(10, root.layoutFontSize - 3)
                  font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
              }

              MouseArea {
                id: searchMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (row) root.activateGlobalSearchRow(row)
                }
              }

              PanelToolTip {
                visible: searchMouse.containsMouse
                text: row && row.kind === "app"
                  ? row.label
                  : row ? row.label + " · " + row.secondary : ""
                panelForeground: "#eeeeee"
                fontFamily: Style.font.menuFamily
              }
            }
          }

          Rectangle {
            id: searchScrollTrack
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 8
            radius: 4
            color: Color.menu.selectedBackground
            visible: searchGrid.contentHeight > searchGrid.height

            Rectangle {
              id: searchScrollThumb
              x: 1
              width: parent.width - 2
              height: Math.max(32, parent.height * searchGrid.visibleArea.heightRatio)
              y: root.scrollThumbY(searchGrid, parent.height, height)
              radius: 3
              color: Color.muted

              MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                property real pressOffset: 0

                onPressed: function(mouse) { pressOffset = mouse.y }
                onPositionChanged: function(mouse) {
                  if (!pressed) return
                  var trackRange = searchScrollTrack.height - searchScrollThumb.height
                  if (trackRange <= 0) return
                  var nextY = searchScrollThumb.y + mouse.y - pressOffset
                  nextY = Math.max(0, Math.min(trackRange, nextY))
                  var contentRange = Math.max(0, searchGrid.contentHeight - searchGrid.height)
                  searchGrid.contentY = contentRange * (nextY / trackRange)
                }
              }
            }
          }
        }

        Item {
          visible: root.activeSection === "apps" && !root.globalSearchActive
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.leftMargin: 12
          Layout.rightMargin: 12
          Layout.topMargin: 0
          Layout.bottomMargin: 0
          clip: true

          GridView {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            property int columnCount: root.layoutColumns > 0
              ? root.layoutColumns
              : Math.max(1, Math.floor(width / root.layoutCellWidth))
            width: root.layoutColumns > 0
              ? Math.min(parent.width - 16, root.layoutColumns * root.layoutCellWidth)
              : parent.width - 16
            cellWidth: width / columnCount
            cellHeight: root.layoutRows > 0 ? root.layoutCellHeight : 128
            height: Math.floor(parent.height / cellHeight) * cellHeight
            snapMode: GridView.SnapToRow
            model: root.filteredAppIds
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 2800

            delegate: Item {
              id: appItem
              required property string modelData
              readonly property var app: root.appForId(modelData)
              width: grid.cellWidth
              height: grid.cellHeight

              property bool isPinned: app ? root.pinnedIds[app.id] === true : false
              property bool isRunning: app ? root.isAppRunning(app) : false

              Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) - 6
                height: width
                radius: width / 2
                color: mouse.containsMouse ? Color.menu.selectedBackground : "transparent"
              }

              Item {
                id: iconBox
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 12
                width: Math.min(root.layoutIconSize, Math.max(1, parent.width - 10))
                height: width

                Image {
                  id: appIcon
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                  asynchronous: true
                  mipmap: true
                  source: root.appLibrary
                    && app && app.icon
                    ? root.appLibrary.iconSource(app.icon)
                    : ""
                }

                Rectangle {
                  anchors.fill: parent
                  // Some desktop entries contain an icon name whose themed
                  // file cannot actually be loaded. Treat every non-ready
                  // state as missing so the grid never shows an empty cell.
                  visible: !app || !app.icon || appIcon.status !== Image.Ready || appIcon.source === ""
                  radius: width / 2
                  color: Color.menu.selectedBackground
                  border.color: Color.menu.border
                  border.width: 1

                  Text {
                    anchors.centerIn: parent
                    text: {
                      var name = root.appLibrary
                        ? root.appLibrary.entryName(app)
                        : String(app ? (app.name || app.id) : "?")
                      return name.length > 0 ? name.charAt(0).toUpperCase() : "?"
                    }
                    color: Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: root.layoutFontSize + 11
                  font.weight: Font.DemiBold
                  }
                }
              }

              Rectangle {
                id: pinBadge
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 4
                anchors.rightMargin: 7
                width: 22
                height: 22
                radius: 11
                color: mouse.containsMouse
                  ? (appItem.isPinned ? Color.accent : Color.menu.selectedBackground)
                  : "transparent"
                opacity: appItem.isPinned || mouse.containsMouse ? 1 : 0
                z: 3

                Text {
                  anchors.centerIn: parent
                  text: "󰐃"
                  color: mouse.containsMouse
                    ? (appItem.isPinned ? Color.menu.background : Color.muted)
                    : (appItem.isPinned ? Color.menu.text : Color.muted)
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.layoutFontSize
                  font.weight: Font.DemiBold
                }

                MouseArea {
                  anchors.fill: parent
                  z: 1
                  onClicked: {
                    if (app) root.togglePinned(app.id)
                  }
                }
              }

              Text {
                id: appLabel
                anchors.top: iconBox.bottom
                anchors.topMargin: 8
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 5
                anchors.rightMargin: 5
                height: 20
                text: root.appLibrary
                  ? root.appLibrary.entryName(app)
                  : String(app ? (app.name || app.id) : "?")
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: root.layoutFontSize
                  font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }

              Text {
                id: appDescription
                anchors.top: appLabel.bottom
                anchors.topMargin: 2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 5
                anchors.rightMargin: 5
                height: 18
                text: root.appLibrary
                  ? root.appLibrary.entrySubtext(app)
                  : ""
                color: Color.muted
                font.family: Style.font.menuFamily
                font.pixelSize: Math.max(10, root.layoutFontSize - 3)
                  font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }

              // The running marker is aligned to the fixed bottom edge of
              // the label area, so one-line and two-line names look identical.
              Rectangle {
                anchors.top: appDescription.bottom
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                width: 8
                height: 8
                radius: 4
                color: "#f5c542"
                border.color: Color.menu.background
                border.width: 1
                opacity: appItem.isRunning ? 1 : 0
                z: 2
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (app) root.launch(app)
                }
              }

              PanelToolTip {
                visible: mouse.containsMouse
                text: {
                  var name = root.appLibrary
                    ? root.appLibrary.entryName(app)
                    : String(app ? (app.name || app.id) : "?")
                  var description = root.appLibrary
                    ? root.appLibrary.entrySubtext(app)
                    : ""
                  return description ? name + " · " + description : name
                }
                panelForeground: "#eeeeee"
                fontFamily: Style.font.menuFamily
              }

            }
          }

          Rectangle {
            id: scrollTrack
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 8
            radius: 4
            color: Color.menu.selectedBackground
            visible: grid.contentHeight > grid.height

            Rectangle {
              id: scrollThumb
              x: 1
              width: parent.width - 2
              height: Math.max(32, parent.height * grid.visibleArea.heightRatio)
              y: root.scrollThumbY(grid, parent.height, height)
              radius: 3
              color: Color.muted

              MouseArea {
                id: scrollThumbMouse
                anchors.fill: parent
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                property real pressOffset: 0

                onPressed: function(mouse) {
                  pressOffset = mouse.y
                }

                onPositionChanged: function(mouse) {
                  if (!pressed) return
                  var trackRange = scrollTrack.height - scrollThumb.height
                  if (trackRange <= 0) return
                  var nextY = scrollThumb.y + mouse.y - pressOffset
                  nextY = Math.max(0, Math.min(trackRange, nextY))
                  var contentRange = Math.max(0, grid.contentHeight - grid.height)
                  grid.contentY = contentRange * (nextY / trackRange)
                }
              }
            }
          }
        }

        Item {
          visible: root.activeSection !== "apps" && !root.globalSearchActive
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.leftMargin: 18
          Layout.rightMargin: 18
          Layout.topMargin: 0
          Layout.bottomMargin: 0
          clip: true

          GridView {
            id: sectionGrid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.top: parent.top
            property int columnCount: Math.max(1, Math.floor(width / 140))
            cellWidth: width / columnCount
            cellHeight: 128
            height: Math.floor(parent.height / cellHeight) * cellHeight
            snapMode: GridView.SnapToRow
            model: root.sectionRowIds
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 2800

            delegate: Item {
              required property string modelData
              readonly property var row: root.sectionRowForId(modelData)
              width: sectionGrid.cellWidth
              height: sectionGrid.cellHeight

              Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) - 6
                height: width
                radius: width / 2
                color: sectionMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 14
                width: 56
                height: 56
                text: row ? (row.icon || "□") : "□"
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: root.layoutFontSize + 20
                  font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }

              Row {
                id: sectionLabelRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 77
                height: 36
                spacing: 6

                Text {
                  width: Math.min(140, implicitWidth)
                  height: sectionLabelRow.height
                  text: row ? row.label : ""
                  color: Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.layoutFontSize
                  font.weight: Font.DemiBold
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  maximumLineCount: 2
                  wrapMode: Text.Wrap
                  elide: Text.ElideNone
                }

                Text {
                  visible: row && row.hasChildren
                  width: visible ? 12 : 0
                  height: sectionLabelRow.height
                  text: "›"
                  color: Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.layoutFontSize
                  font.weight: Font.DemiBold
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
              }

              MouseArea {
                id: sectionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (row) root.activateSectionRow(row)
                }
              }

              PanelToolTip {
                visible: sectionMouse.containsMouse
                text: row ? row.label : ""
                panelForeground: "#eeeeee"
                fontFamily: Style.font.menuFamily
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 82
          Layout.bottomMargin: 16
          color: "transparent"

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 0
            color: "transparent"
          }

          ListView {
            id: navigationList
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, 100 * Math.max(1, count))
            height: parent.height
            orientation: ListView.Horizontal
            spacing: 0
            clip: true
            model: root.globalSearchActive ? root.searchNavigationIds : root.navigationIds
            interactive: false

            delegate: Item {
              required property string modelData
              readonly property var item: root.navigationItemForId(modelData)
              width: navigationList.width / Math.max(1, navigationList.count)
              height: navigationList.height

              Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 10
                color: root.navigationActive(item.id) ? Color.menu.selectedBackground : "transparent"
              }

              Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                  width: 100
                  text: item.icon || "□"
                  color: Color.muted
                  font.family: Style.font.menuFamily
                  font.pixelSize: root.layoutFontSize + 8
                  font.weight: Font.DemiBold
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  width: 100
                  text: item.label
                  color: Color.muted
                  font.family: Style.font.menuFamily
                  font.pixelSize: Math.max(10, root.layoutFontSize - 2)
                  font.weight: Font.DemiBold
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  if (root.globalSearchActive) root.selectSearchCategory(item.id)
                  else root.selectSection(item.id, item.id === "apps")
                }
              }
            }
          }
        }
      }
    }
  }
}
