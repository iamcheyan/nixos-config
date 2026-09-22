import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "DesktopLayout.js" as DesktopLayout

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var items: []
  property string itemsJson: ""
  property var layoutState: DesktopLayout.empty()
  property string desktopPath: Quickshell.env("HOME") + "/Desktop"
  property string selectedId: ""
  property var selectedIds: []
  property int iconSize: 48
  property int cellW: 96
  property int cellH: 104
  property int padLeft: 24
  property int padRight: 24
  property int padBottom: 24
  readonly property int maxItems: 256
  readonly property int maxListChars: 262144
  readonly property int maxNameLength: 120
  property var pendingTrust: null
  property string pendingTrustScreen: ""
  property string renamingId: ""
  property string renamingScreen: ""
  property bool renameBusy: false
  property int positionWrites: 0
  property string dragId: ""
  property var dragEntry: null
  property string dragOriginScreen: ""
  property string dragHoverScreen: ""
  property real dragSceneX: 0
  property real dragSceneY: 0
  property real dragGrabX: 0
  property real dragGrabY: 0

  readonly property string home: Quickshell.env("HOME")
  readonly property string pythonBin: Quickshell.env("ANCHOR_SHELL_PYTHON") || "python3"
  readonly property string anchorConfigDir: Quickshell.env("ANCHOR_SHELL_CONFIG_DIR")
    || (home + "/.config/anchor-shell")
  readonly property string anchorStateDir: Quickshell.env("ANCHOR_SHELL_STATE_DIR")
    || (home + "/.local/state/anchor-shell")
  readonly property string pluginDir: (manifest && manifest.__sourceDir)
    ? String(manifest.__sourceDir)
    : (anchorConfigDir + "/plugins/henri.desktop-icons")
  readonly property string indexScript: pluginDir + "/bin/desktop-index"
  readonly property string addScript: pluginDir + "/bin/add-to-desktop"
  readonly property string hyperlinkScript: pluginDir + "/bin/create-hyperlink"
  readonly property string positionsPath: anchorStateDir + "/desktop-icon-positions.json"
  readonly property string screenTopology: {
    var names = []
    for (var i = 0; i < Quickshell.screens.length; i++)
      names.push(String(Quickshell.screens[i].name || "default"))
    names.sort()
    return names.join("|")
  }

  function screenNames() {
    var names = root.screenTopology ? root.screenTopology.split("|") : []
    return names.length > 0 && names[0] ? names : ["default"]
  }

  function screenAtPoint(x, y) {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && x >= screen.x && x < screen.x + screen.width
          && y >= screen.y && y < screen.y + screen.height)
        return screen
    }
    return null
  }

  function outputScale() {
    var ratio = 1
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      var candidate = Number(screens[i] && screens[i].devicePixelRatio)
      if (candidate > ratio)
        ratio = candidate
    }
    return ratio
  }

  readonly property int iconPixels: Math.max(1, Math.round(iconSize * outputScale()))

  function iconIsRaster(url) {
    var src = String(url || "").toLowerCase().split("?")[0]
    return !(src.endsWith(".svg") || src.endsWith(".svgz"))
  }

  function updateDragPointer(sceneX, sceneY) {
    root.dragSceneX = sceneX
    root.dragSceneY = sceneY
    var screen = root.screenAtPoint(sceneX, sceneY)
    if (screen)
      root.dragHoverScreen = String(screen.name || "default")
  }

  function beginDrag(item, screenName, sceneX, sceneY, grabX, grabY) {
    root.dragEntry = item || null
    root.dragOriginScreen = screenName || ""
    root.dragHoverScreen = screenName || ""
    root.dragGrabX = grabX
    root.dragGrabY = grabY
    root.dragId = item && item.id ? String(item.id) : ""
    root.updateDragPointer(sceneX, sceneY)
  }

  function clearDrag() {
    root.dragId = ""
    root.dragEntry = null
    root.dragOriginScreen = ""
    root.dragHoverScreen = ""
  }

  // Labwc opens the desktop menu from Alt+Space, at the pointer.
  // The icon layer has to own the whole output so a selection can start
  // anywhere; this hands that right-click back to the compositor.
  function showRootMenu() {
    Quickshell.execDetached(["wtype", "-M", "alt", "-k", "space", "-m", "alt"])
  }

  function gridFor(screen) {
    var height = screen && screen.height ? screen.height : 1080
    var top = root.padTopFor(screen)
    return {
      left: root.padLeftFor(screen),
      top: top,
      cellW: root.cellW,
      cellH: root.cellH,
      rows: Math.max(1, Math.floor((height - top - root.padBottom) / root.cellH))
    }
  }

  function reconcileLayout() {
    root.layoutState = DesktopLayout.normalize(
      root.layoutState,
      root.items,
      root.screenNames(),
      root.gridFor(Quickshell.screens && Quickshell.screens[0])
    )
  }

  function snapForScreen(screen, x, y) {
    var left = root.padLeftFor(screen)
    var top = root.padTopFor(screen)
    var col = Math.max(0, Math.round((x - left) / root.cellW))
    var row = Math.max(0, Math.round((y - top) / root.cellH))
    return {
      x: Math.min(left + col * root.cellW, Math.max(left, screen.width - root.cellW)),
      y: Math.min(top + row * root.cellH, Math.max(top, screen.height - root.cellH))
    }
  }

  function moveItemToScreen(itemId, fromScreen, screenName, x, y) {
    if (!itemId || !screenName)
      return
    var target = null
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "default") === screenName) {
        target = screens[i]
        break
      }
    }
    if (!target)
      return
    var snapped = root.snapForScreen(target, x, y)
    var grid = root.gridFor(target)
    var targetCell = DesktopLayout.cellFromPixel(snapped.x, snapped.y, grid)
    root.layoutState = DesktopLayout.moveToScreen(
      root.layoutState,
      String(itemId),
      fromScreen || DesktopLayout.homeOf(root.layoutState, String(itemId)),
      screenName,
      targetCell
    )
    root.savePositions()
  }

  function moveItemWithinScreen(screenName, itemId, sourceCell, targetCell) {
    var id = String(itemId)
    var home = DesktopLayout.homeOf(root.layoutState, id)
    if (root.screenNames().length === 1 && home && home !== screenName) {
      // A drag while monitors are merged is an explicit move to the merged
      // display. Remove the old home so reconnecting monitors cannot create a
      // duplicate copy of the same icon.
      root.layoutState = DesktopLayout.moveToScreen(
        root.layoutState, id, home, screenName, targetCell
      )
    } else {
      root.layoutState = DesktopLayout.moveOrSwap(
        root.layoutState, screenName, id, sourceCell, targetCell
      )
    }
    root.savePositions()
  }

  function itemsForScreen(screenName) {
    var ids = DesktopLayout.visibleIds(root.layoutState, root.items, root.screenNames(), screenName)
    var wanted = {}
    for (var i = 0; i < ids.length; i++)
      wanted[ids[i]] = true
    var result = []
    for (var j = 0; j < root.items.length; j++) {
      if (wanted[root.items[j].id])
        result.push(root.items[j])
    }
    return result
  }

  function padTopFor(screen) {
    var bar = shell && shell.bar ? shell.bar : null
    var barSize = bar && bar.barSize ? bar.barSize : 26
    var extra = 24
    if (bar && bar.position === "top" && !bar.barHidden)
      return barSize + extra
    return extra
  }

  function padLeftFor(screen) {
    var bar = shell && shell.bar ? shell.bar : null
    var barSize = bar && bar.barSize ? bar.barSize : 26
    if (bar && bar.position === "left" && !bar.barHidden)
      return barSize + 24
    return root.padLeft
  }

  function isTrash(item) {
    return !!(item && item.kind === "trash")
  }

  function isUntrustedLauncher(item) {
    return !!(item && item.kind === "launcher" && item.trusted !== true)
  }

  function isBlockedIconUrl(value) {
    var lower = String(value || "").toLowerCase()
    return lower.indexOf("http:") === 0
      || lower.indexOf("https:") === 0
      || lower.indexOf("ftp:") === 0
      || lower.indexOf("ftps:") === 0
      || lower.indexOf("sftp:") === 0
      || lower.indexOf("smb:") === 0
      || lower.indexOf("nfs:") === 0
      || lower.indexOf("dav:") === 0
      || lower.indexOf("data:") === 0
      || lower.indexOf("qrc:") === 0
      || lower.indexOf("image:") === 0
      || lower.indexOf("qt:") === 0
  }

  function isLocalFileUrl(value) {
    var icon = String(value || "")
    if (icon.indexOf("file://") !== 0)
      return false
    var rest = icon.slice(7)
    return rest.charAt(0) === "/" && rest.charAt(1) !== "/"
  }

  function plainText(value, maxLen) {
    var text = String(value || "").replace(/[<>\u0001-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, " ")
    text = text.replace(/\s+/g, " ").trim()
    var limit = maxLen || root.maxNameLength
    if (text.length > limit)
      text = text.slice(0, limit)
    return text
  }

  function fallbackIcon(item) {
    return Quickshell.iconPath(item && item.isDir ? "folder" : "text-x-generic", true)
  }

  function localFileUrl(path) {
    var value = String(path || "")
    if (root.isBlockedIconUrl(value))
      return ""
    if (root.isLocalFileUrl(value))
      return value
    if (!value || value.charAt(0) !== "/" || value.indexOf("//") === 0)
      return ""
    if (value.indexOf("://") !== -1)
      return ""
    return Util.fileUrl(value)
  }

  function safeIconSource(icon, item) {
    var value = String(icon || "")
    var fallback = root.fallbackIcon(item)
    if (!value || root.isBlockedIconUrl(value))
      return fallback
    if (root.isLocalFileUrl(value))
      return value
    if (value.charAt(0) === "/") {
      var local = root.localFileUrl(value)
      return local || fallback
    }
    if (value.indexOf("/") >= 0 || value.indexOf("\\") >= 0 || value.indexOf(":") >= 0)
      return fallback
    if (!/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(value))
      return fallback
    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0)
      return themed
    return fallback
  }

  function iconSource(item) {
    if (!item) return ""
    var preview = String(item.preview || "")
    if (preview) {
      var previewUrl = root.localFileUrl(preview)
      if (previewUrl)
        return previewUrl
    }
    return root.safeIconSource(item.icon, item)
  }

  function sanitizeItem(item) {
    if (!item || typeof item !== "object")
      return null
    var kind = root.plainText(item.kind, 32)
    var icon = String(item.icon || "")
    var preview = String(item.preview || "")
    if (root.isBlockedIconUrl(icon))
      icon = ""
    if (root.isBlockedIconUrl(preview))
      preview = ""
    return {
      id: String(item.id || "").slice(0, 255),
      name: root.plainText(item.name, root.maxNameLength) || "Item",
      path: String(item.path || ""),
      icon: icon,
      preview: preview,
      isDir: !!item.isDir,
      kind: kind,
      trusted: item.trusted === true || kind !== "launcher"
    }
  }

  function refresh() {
    if (root.renameBusy)
      return
    if (!listProc.running)
      listProc.running = true
  }

  function canRename(item) {
    return !!(item && item.path && !root.isTrash(item) && !root.renameBusy)
  }

  function isRenamingItem(item, screenName) {
    return !!(item && root.renamingId && root.renamingId === item.id
      && root.renamingScreen === screenName)
  }

  function beginRename(item, screenName) {
    if (!root.canRename(item))
      return
    root.selectItem(item, 0)
    root.renamingScreen = screenName || ""
    root.renamingId = item.id
  }

  function cancelRename() {
    root.renamingId = ""
    root.renamingScreen = ""
  }

  function renameItemPos(oldId, newId) {
    if (!oldId || !newId || oldId === newId)
      return
    var next = JSON.parse(JSON.stringify(root.layoutState || DesktopLayout.empty()))
    var dirty = false
    for (var screen in next.screens) {
      if (!next.screens[screen] || !next.screens[screen][oldId])
        continue
      next.screens[screen][newId] = next.screens[screen][oldId]
      delete next.screens[screen][oldId]
      dirty = true
    }
    if (!dirty)
      return
    root.layoutState = next
    root.savePositions()
  }

  function commitRename(item, newName) {
    root.cancelRename()
    var name = String(newName || "").replace(/\s+/g, " ").trim()
    if (!item || !item.path || root.isTrash(item) || !name || root.renameBusy)
      return
    if (name === String(item.name || ""))
      return
    root.renameBusy = true
    renameProc.oldId = item.id
    renameProc.command = [
      root.pythonBin,
      root.indexScript,
      "--rename",
      item.path,
      "--to",
      name
    ]
    renameProc.running = true
  }

  function visualOrder(screenName) {
    var items = root.itemsForScreen(screenName)
    if (!items || items.length === 0)
      return []
    var ps = (root.layoutState.screens && screenName)
      ? (root.layoutState.screens[screenName] || {})
      : {}
    var arr = items.slice()
    arr.sort(function(a, b) {
      var pa = ps[a.id] || {}
      var pb = ps[b.id] || {}
      var ca = pa.col === undefined ? 1e9 : pa.col
      var cb = pb.col === undefined ? 1e9 : pb.col
      if (ca !== cb)
        return ca - cb
      var ra = pa.row === undefined ? 1e9 : pa.row
      var rb = pb.row === undefined ? 1e9 : pb.row
      return ra - rb
    })
    return arr
  }

  function moveSelectionDirection(dx, dy, screenName) {
    var items = root.itemsForScreen(screenName)
    if (!items || items.length === 0)
      return
    var cells = (root.layoutState.screens && root.layoutState.screens[screenName]) || {}
    var current = null
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === root.selectedId) {
        current = cells[items[i].id] || null
        break
      }
    }
    if (!current) {
      root.selectedId = items[0].id
      root.selectedIds = [root.selectedId]
      return
    }
    var best = null
    var bestScore = 1e9
    for (var j = 0; j < items.length; j++) {
      if (items[j].id === root.selectedId)
        continue
      var cell = cells[items[j].id]
      if (!cell)
        continue
      var dcol = cell.col - current.col
      var drow = cell.row - current.row
      if (dx > 0 && dcol <= 0)
        continue
      if (dx < 0 && dcol >= 0)
        continue
      if (dy > 0 && drow <= 0)
        continue
      if (dy < 0 && drow >= 0)
        continue
      var primary = dx !== 0 ? Math.abs(dcol) : Math.abs(drow)
      var secondary = dx !== 0 ? Math.abs(drow) : Math.abs(dcol)
      var score = primary * 1000 + secondary
      if (score < bestScore) {
        bestScore = score
        best = items[j]
      }
    }
    if (!best)
      return
    root.selectedId = best.id
    root.selectedIds = [root.selectedId]
  }

  function moveSelection(delta, screenName) {
    var order = root.visualOrder(screenName)
    if (order.length === 0)
      return
    var idx = -1
    for (var i = 0; i < order.length; i++) {
      if (order[i].id === root.selectedId) {
        idx = i
        break
      }
    }
    if (idx === -1)
      idx = 0
    else {
      idx = (idx + delta) % order.length
      if (idx < 0)
        idx += order.length
    }
    root.selectedId = order[idx].id
    root.selectedIds = [root.selectedId]
  }

  function isSelected(itemId) {
    return root.selectedIds.indexOf(String(itemId)) >= 0
  }

  function clearSelection() {
    root.selectedId = ""
    root.selectedIds = []
  }

  function selectItem(item, modifiers) {
    if (!item || !item.id)
      return
    var id = String(item.id)
    var multi = !!(modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
    var next = multi ? root.selectedIds.slice() : []
    var index = next.indexOf(id)
    if (multi && (modifiers & Qt.ControlModifier) && index >= 0)
      next.splice(index, 1)
    else if (index < 0)
      next.push(id)
    root.selectedIds = next
    root.selectedId = next.length > 0 ? next[0] : ""
  }

  function selectItems(items) {
    var next = []
    for (var i = 0; i < items.length; i++) {
      var id = String(items[i].id)
      if (next.indexOf(id) < 0)
        next.push(id)
    }
    root.selectedIds = next
    root.selectedId = next.length > 0 ? next[0] : ""
  }

  function openItem(item) {
    if (!item || !item.path) return
    Quickshell.execDetached([root.pythonBin, root.indexScript, "--open", item.path])
  }

  function openOrConfirm(item, screenName) {
    if (!item || !item.path) return
    if (root.isUntrustedLauncher(item)) {
      root.pendingTrust = item
      root.pendingTrustScreen = screenName || ""
      return
    }
    root.openItem(item)
  }

  function clearTrustPrompt() {
    root.pendingTrust = null
    root.pendingTrustScreen = ""
  }

  function allowLaunching(item) {
    if (!item || !item.path) return
    Quickshell.execDetached([root.pythonBin, root.indexScript, "--trust", item.path])
    root.clearTrustPrompt()
    Qt.callLater(root.refresh)
  }

  function trustAndOpen(item) {
    if (!item || !item.path) return
    Quickshell.execDetached([root.pythonBin, root.indexScript, "--trust-and-open", item.path])
    root.clearTrustPrompt()
    Qt.callLater(root.refresh)
  }

  function trashUrls(urls) {
    if (!urls || urls.length === 0) return
    var cmd = [root.pythonBin, root.indexScript, "--trash"]
    var limit = Math.min(urls.length, root.maxItems)
    for (var i = 0; i < limit; i++)
      cmd.push(String(urls[i]))
    Quickshell.execDetached(cmd)
    Qt.callLater(root.refresh)
  }

  function trashItem(item) {
    if (!item || !item.path || root.isTrash(item)) return
    root.trashUrls([item.path])
  }

  function revealItem(item) {
    if (item && item.path)
      Quickshell.execDetached(["nautilus", "--select", item.path])
    else
      root.openDesktopFolder()
  }

  function newFolder() {
    Quickshell.execDetached([
      "bash", "-lc",
      "d=" + Util.shellQuote(root.desktopPath) + "; " +
      "n='New Folder'; p=\"$d/$n\"; i=2; " +
      "while [ -e \"$p\" ]; do p=\"$d/$n $i\"; i=$((i+1)); done; " +
      "mkdir -p \"$p\""
    ])
    Qt.callLater(root.refresh)
  }

  function newShortcut() {
    Quickshell.execDetached([root.hyperlinkScript, "--directory", root.desktopPath])
  }

  function pinApp() {
    Quickshell.execDetached([root.addScript, "--pick-app"])
  }

  function addFiles() {
    Quickshell.execDetached([root.addScript, "--pick-files"])
  }

  function openDesktopFolder() {
    Quickshell.execDetached(["xdg-open", root.desktopPath])
  }

  function switchWallpaper() {
    Quickshell.execDetached([
      "bash", "-lc",
      "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""
    ])
  }

  function placeUrls(urls, mode) {
    if (!urls || urls.length === 0) return
    var cmd = [root.pythonBin, root.indexScript, "--mode", mode || "copy", "--place"]
    var limit = Math.min(urls.length, root.maxItems)
    for (var i = 0; i < limit; i++)
      cmd.push(String(urls[i]))
    Quickshell.execDetached(cmd)
    Qt.callLater(root.refresh)
  }

  function dropMode(drop) {
    if (!drop) return "copy"
    if (drop.proposedAction === Qt.LinkAction) return "link"
    if (drop.proposedAction === Qt.MoveAction) return "move"
    return "copy"
  }

  function applyList(raw) {
    var text = String(raw || "").trim()
    if (!text)
      return
    if (text.length > root.maxListChars) {
      console.warn("desktop-icons: index output exceeded resource ceiling")
      return
    }
    try {
      var data = JSON.parse(text)
      var incoming = Array.isArray(data.items) ? data.items.slice(0, root.maxItems) : []
      var items = []
      for (var i = 0; i < incoming.length; i++) {
        var item = root.sanitizeItem(incoming[i])
        if (item && item.id)
          items.push(item)
      }
      var desktop = data.desktop ? String(data.desktop) : root.desktopPath
      var next = JSON.stringify({ desktop: desktop, items: items })
      if (next === root.itemsJson)
        return
      root.desktopPath = desktop
      root.itemsJson = next
      root.items = items
      Qt.callLater(root.reconcileLayout)
      if (root.pendingTrust && root.pendingTrust.id) {
        var pendingId = root.pendingTrust.id
        var stillUntrusted = false
        for (var j = 0; j < items.length; j++) {
          if (items[j].id === pendingId && root.isUntrustedLauncher(items[j])) {
            stillUntrusted = true
            break
          }
        }
        if (!stillUntrusted)
          root.clearTrustPrompt()
      }
    } catch (e) {
      console.warn("desktop-icons: failed to parse index:", e)
    }
  }

  function applyPositions(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      // Keep the raw model until the desktop index arrives. Normalizing an
      // empty item list here would discard saved homes during startup.
      root.layoutState = data && typeof data === "object"
        ? data
        : DesktopLayout.empty()
    } catch (e) {
      root.layoutState = DesktopLayout.empty()
    }
  }

  function savePositions() {
    root.positionWrites += 1
    posFile.setText(JSON.stringify(root.layoutState || DesktopLayout.empty(), null, 2) + "\n")
  }

  Process {
    id: listProc
    command: [root.pythonBin, root.indexScript]
    stdout: StdioCollector {
      onStreamFinished: root.applyList(text)
    }
  }

  Process {
    id: renameProc
    property string oldId: ""
    stdout: StdioCollector {
      id: renameOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        try {
          var data = JSON.parse(String(renameOut.text || "").trim())
          if (renameProc.oldId && data && data.id) {
            root.renameItemPos(renameProc.oldId, data.id)
          if (root.selectedId === renameProc.oldId)
            root.selectedId = data.id
          var renamedSelection = root.selectedIds.slice()
          for (var selectedIndex = 0; selectedIndex < renamedSelection.length; selectedIndex++) {
            if (renamedSelection[selectedIndex] === renameProc.oldId)
              renamedSelection[selectedIndex] = data.id
          }
          root.selectedIds = renamedSelection
          }
        } catch (e) {
        }
      }
      renameProc.oldId = ""
      root.renameBusy = false
      Qt.callLater(root.refresh)
    }
  }

  FileView {
    id: posFile
    path: root.positionsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyPositions(text())
    onLoadFailed: root.layoutState = DesktopLayout.empty()
    onFileChanged: {
      if (root.positionWrites > 0) {
        root.positionWrites -= 1
        return
      }
      reload()
    }
  }

  // Watch the Desktop folder itself so icons appear, move, or get deleted
  // immediately instead of waiting for the fallback poll below.
  FileView {
    id: desktopWatch
    path: root.desktopPath
    watchChanges: true
    printErrors: false
    onLoaded: root.refresh()
    onFileChanged: root.refresh()
    onLoadFailed: root.refresh()
  }

  // Safety-net poll. The directory watch above handles the common case
  // instantly; this keeps add/delete responsive if the watch ever misses.
  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      // Repeater delegates with required properties cannot see outer ids.
      property var host: root

      screen: modelData
      visible: true
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "desktop-icons"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      anchors { top: true; bottom: true; left: true; right: true }
      // Own the whole output so a selection can start from any edge.
      // Empty right-clicks are forwarded to Labwc's root menu.
      mask: Region {
        Region { item: emptyMouse }
        Region { item: menuBox }
        Region { item: trustBox }
      }

      readonly property string screenName: modelData.name || "default"
      property var visibleItems: []
      property int padTop: host.padTopFor(modelData)
      property int padLeft: host.padLeftFor(modelData)
      property string menuKind: ""
      property var menuItem: null
      property real menuX: 0
      property real menuY: 0
      property bool dropping: false
      property int emptyClicks: 0
      property bool marqueeActive: false
      property bool marqueeMoved: false
      property bool suppressEmptyClick: false
      property real marqueeStartX: 0
      property real marqueeStartY: 0
      property real marqueeEndX: 0
      property real marqueeEndY: 0
      property bool _initialized: false
      property var _knownIds: ({})

      function layoutPos(index) {
        var availH = Math.max(host.cellH, panel.height - panel.padTop - host.padBottom)
        var rows = Math.max(1, Math.floor(availH / host.cellH))
        var col = Math.floor(index / rows)
        var row = index % rows
        return {
          x: panel.padLeft + col * host.cellW,
          y: panel.padTop + row * host.cellH
        }
      }

      function posFor(item, index) {
        return DesktopLayout.position(
          host.layoutState, panel.screenName, item ? item.id : "", index,
          host.gridFor(panel.modelData)
        )
      }

      function snap(x, y) {
        var grid = host.gridFor(panel.modelData)
        return DesktopLayout.pixelFromCell(
          DesktopLayout.cellFromPixel(x, y, grid), grid
        )
      }

      function itemsMatch(current, next) {
        if (!current || !next || current.length !== next.length)
          return false
        for (var i = 0; i < next.length; i++) {
          var a = current[i]
          var b = next[i]
          if (!a || !b || a.id !== b.id || a.name !== b.name || a.icon !== b.icon
              || a.preview !== b.preview || a.trusted !== b.trusted
              || a.isDir !== b.isDir || a.kind !== b.kind || a.path !== b.path)
            return false
        }
        return true
      }

      function refreshVisibleItems() {
        var next = host.itemsForScreen(panel.screenName)
        if (panel.itemsMatch(panel.visibleItems, next))
          return
        panel.visibleItems = next
      }

      function itemAt(x, y, exceptId) {
        for (var i = 0; i < panel.visibleItems.length; i++) {
          var item = panel.visibleItems[i]
          if (exceptId && item.id === exceptId)
            continue
          var pos = panel.posFor(item, i)
          if (x >= pos.x && x < pos.x + host.cellW && y >= pos.y && y < pos.y + host.cellH)
            return item
        }
        return null
      }

      function selectMarquee() {
        var left = Math.min(panel.marqueeStartX, panel.marqueeEndX)
        var right = Math.max(panel.marqueeStartX, panel.marqueeEndX)
        var top = Math.min(panel.marqueeStartY, panel.marqueeEndY)
        var bottom = Math.max(panel.marqueeStartY, panel.marqueeEndY)
        var selected = []
        for (var i = 0; i < panel.visibleItems.length; i++) {
          var pos = panel.posFor(panel.visibleItems[i], i)
          if (pos.x + host.cellW > left && pos.x < right
              && pos.y + host.cellH > top && pos.y < bottom)
            selected.push(panel.visibleItems[i])
        }
        host.selectItems(selected)
      }

      function trustIconPos() {
        var item = host.pendingTrust
        if (!item)
          return null
        for (var i = 0; i < panel.visibleItems.length; i++) {
          if (panel.visibleItems[i].id === item.id)
            return panel.posFor(panel.visibleItems[i], i)
        }
        return null
      }

      // Place newly added icons at the bottom-most free grid cell (just past
      // the last occupied icon), skipping any cell already taken. This keeps
      // them out of the way of manually dragged icons while still landing at
      // the bottom of the list when the grid is tidy. Existing icons keep
      // their positions; stale positions for removed items are cleaned up.
      // Triggered only on add/remove, never on a drag or a routine refresh.
      function assignMissing() {
        host.reconcileLayout()
        host.savePositions()
      }

      // Detect add/remove (item id set change) and place only new icons.
      // First load still assigns missing positions so unsaved items do not
      // land on top of dragged ones; existing saved positions stay put.
      function maybeRepack() {
        var cur = {}
        for (var i = 0; i < panel.visibleItems.length; i++)
          cur[panel.visibleItems[i].id] = true
        if (!panel._initialized) {
          panel._knownIds = cur
          panel._initialized = true
          if (panel.width > host.cellW && panel.height > host.cellH)
            panel.assignMissing()
          return
        }
        var changed = false
        for (var id in cur)
          if (!panel._knownIds[id])
            changed = true
        for (var id in panel._knownIds)
          if (!cur[id])
            changed = true
        panel._knownIds = cur
        if (changed)
          panel.assignMissing()
      }

      function closeMenu() {
        menuKind = ""
        menuItem = null
      }

      function openEmptyMenu(mouse) {
        menuKind = "empty"
        menuItem = null
        menuX = mouse.x
        menuY = mouse.y
      }

      function openItemMenu(item, iconItem, mouse) {
        menuKind = "item"
        menuItem = item
        var p = contentItem.mapFromItem(iconItem, mouse.x, mouse.y)
        menuX = p.x
        menuY = p.y
      }

      readonly property var menuEntries: {
        if (menuKind === "item") {
          if (host.isTrash(menuItem))
            return [
              { action: "open", label: "Open Trash" },
              { action: "files", label: "Show in Files" }
            ]
          var renameAndManage = [
            { action: "rename", label: "Rename" },
            { action: "files", label: "Show in Files" },
            { action: "trash", label: "Move to Trash" }
          ]
          if (host.isUntrustedLauncher(menuItem))
            return [
              { action: "trust-open", label: "Trust and Open" },
              { action: "trust", label: "Allow launching" }
            ].concat(renameAndManage)
          return [
            { action: "open", label: "Open" }
          ].concat(renameAndManage)
        }
        if (menuKind === "empty")
          return [
            { action: "folder", label: "New Folder" },
            { action: "shortcut", label: "New Shortcut…" },
            { action: "pin", label: "Pin application…" },
            { action: "addfiles", label: "Add files…" },
            { action: "files", label: "Open Desktop Folder" },
            { action: "refresh", label: "Refresh" }
          ]
        return []
      }

      Timer {
        id: emptyClickTimer
        interval: 2500
        repeat: false
        onTriggered: panel.emptyClicks = 0
      }

      MouseArea {
        id: emptyMouse
        z: 0
        anchors.fill: parent
        // Blank desktop input handles clicks only to dismiss plugin UI. Right
        // clicks on truly transparent wallpaper remain available to Labwc.
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        focus: true
        onActiveFocusChanged: {
          if (!activeFocus && !host.renamingId) {
            host.clearSelection()
            panel.closeMenu()
          }
        }
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            var dismiss = panel.menuKind !== "" || host.pendingTrust
            panel.closeMenu()
            host.clearTrustPrompt()
            if (!dismiss)
              host.showRootMenu()
            return
          }
          if (mouse.button !== Qt.LeftButton)
            return
          panel.marqueeActive = true
          panel.marqueeMoved = false
          panel.suppressEmptyClick = false
          panel.marqueeStartX = mouse.x
          panel.marqueeStartY = mouse.y
          panel.marqueeEndX = mouse.x
          panel.marqueeEndY = mouse.y
          if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
            host.clearSelection()
          emptyMouse.forceActiveFocus()
          panel.closeMenu()
        }
        onPositionChanged: function(mouse) {
          if (!panel.marqueeActive || !(mouse.buttons & Qt.LeftButton))
            return
          panel.marqueeEndX = mouse.x
          panel.marqueeEndY = mouse.y
          if (Math.abs(panel.marqueeEndX - panel.marqueeStartX) > 6
              || Math.abs(panel.marqueeEndY - panel.marqueeStartY) > 6)
            panel.marqueeMoved = true
        }
        onReleased: function(mouse) {
          if (mouse.button !== Qt.LeftButton || !panel.marqueeActive)
            return
          if (panel.marqueeMoved) {
            panel.selectMarquee()
            panel.suppressEmptyClick = true
          }
          panel.marqueeActive = false
        }
        Keys.onPressed: function(event) {
          if (host.renamingId) {
            if (event.key === Qt.Key_Escape)
              host.cancelRename()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (host.pendingTrust)
              host.clearTrustPrompt()
            panel.closeMenu()
            event.accepted = true
          } else if (event.key === Qt.Key_F2 && host.selectedIds.length === 1) {
            for (var r = 0; r < panel.visibleItems.length; r++) {
              if (panel.visibleItems[r].id === host.selectedId) {
                host.beginRename(panel.visibleItems[r], panel.screenName)
                break
              }
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Delete && host.selectedIds.length > 0) {
            var paths = []
            for (var i = 0; i < panel.visibleItems.length; i++) {
              if (host.isSelected(panel.visibleItems[i].id) && panel.visibleItems[i].path)
                paths.push(panel.visibleItems[i].path)
            }
            host.trashUrls(paths)
            host.clearSelection()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            for (var j = 0; j < panel.visibleItems.length; j++) {
              if (panel.visibleItems[j].id === host.selectedId) {
                host.openOrConfirm(panel.visibleItems[j], panel.screenName)
                break
              }
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            host.moveSelection(event.modifiers & Qt.ShiftModifier ? -1 : 1, panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            host.moveSelection(-1, panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            host.moveSelectionDirection(-1, 0, panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            host.moveSelectionDirection(1, 0, panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            host.moveSelectionDirection(0, -1, panel.screenName)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            host.moveSelectionDirection(0, 1, panel.screenName)
            event.accepted = true
          }
        }
        onClicked: function(mouse) {
          if (panel.suppressEmptyClick) {
            panel.suppressEmptyClick = false
            return
          }
          if (host.renamingId) {
            emptyMouse.forceActiveFocus()
            panel.emptyClicks = 0
            panel.closeMenu()
            return
          }
          host.clearSelection()
          emptyMouse.forceActiveFocus()
          panel.closeMenu()
          if (host.pendingTrust) {
            host.clearTrustPrompt()
            panel.emptyClicks = 0
            if (mouse.button === Qt.RightButton)
              panel.openEmptyMenu(mouse)
            return
          }
          if (mouse.button === Qt.RightButton)
            return
          panel.emptyClicks += 1
          emptyClickTimer.restart()
          if (panel.emptyClicks >= 5) {
            panel.emptyClicks = 0
            host.switchWallpaper()
          }
        }
      }

      Item {
        id: dragGhost
        z: 40
        width: host.cellW
        height: host.cellH
        enabled: false
        visible: host.dragId !== "" && host.dragEntry
                 && host.dragHoverScreen === panel.screenName
                 && host.dragOriginScreen !== panel.screenName
        x: host.dragSceneX - panel.modelData.x - host.dragGrabX
        y: host.dragSceneY - panel.modelData.y - host.dragGrabY
        opacity: 0.96

        Column {
          anchors.fill: parent
          anchors.margins: 6
          spacing: 4

          Item {
            width: host.iconSize
            height: host.iconSize
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
              anchors.fill: parent
              source: host.iconSource(host.dragEntry)
              fillMode: Image.PreserveAspectFit
              asynchronous: false
              cache: false
              smooth: true
              sourceSize.width: host.iconIsRaster(source) ? host.iconPixels : 0
              sourceSize.height: host.iconIsRaster(source) ? host.iconPixels : 0
            }
          }

          Text {
            width: parent.width
            text: host.plainText(host.dragEntry ? host.dragEntry.name : "")
            textFormat: Text.PlainText
            color: "white"
            style: Text.Outline
            styleColor: "#cc000000"
            font.pixelSize: 12
            font.family: Style.fontFamily
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }

      Rectangle {
        id: marqueeBox
        visible: panel.marqueeActive && panel.marqueeMoved
        z: 4
        x: Math.min(panel.marqueeStartX, panel.marqueeEndX)
        y: Math.min(panel.marqueeStartY, panel.marqueeEndY)
        width: Math.abs(panel.marqueeEndX - panel.marqueeStartX)
        height: Math.abs(panel.marqueeEndY - panel.marqueeStartY)
        color: Qt.rgba(0.25, 0.55, 1.0, 0.16)
        border.width: 1
        border.color: Qt.rgba(0.45, 0.75, 1.0, 0.85)
      }

      DropArea {
        z: 0
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: panel.dropping = true
        onExited: panel.dropping = false
        onDropped: function(drop) {
          panel.dropping = false
          var urls = []
          if (drop.urls) {
            for (var i = 0; i < drop.urls.length; i++)
              urls.push(String(drop.urls[i]))
          }
          if (urls.length > 0) {
            drop.acceptProposedAction()
            var target = panel.itemAt(drop.x, drop.y, "")
            if (target && host.isTrash(target))
              host.trashUrls(urls)
            else
              host.placeUrls(urls, host.dropMode(drop))
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: panel.dropping
        color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 2
        border.color: Qt.rgba(1, 1, 1, 0.35)
        z: 5
      }

      Item {
        id: inputLayer
        x: 0
        y: 0
        width: {
          var result = 1
          for (var i = 0; i < panel.visibleItems.length; i++) {
            var item = panel.visibleItems[i]
            var pos = panel.posFor(item, i)
            result = Math.max(result, pos.x + panel.host.cellW)
          }
          return result
        }
        height: {
          var result = 1
          for (var i = 0; i < panel.visibleItems.length; i++) {
            var item = panel.visibleItems[i]
            var pos = panel.posFor(item, i)
            result = Math.max(result, pos.y + panel.host.cellH)
          }
          return result
        }

        Repeater {
        model: panel.visibleItems

        Item {
          id: iconRoot
          required property var modelData
          required property int index

          width: panel.host.cellW
          height: panel.host.cellH
          z: iconMouse.drag.active ? 6 : 2
          opacity: (panel.host.dragId === iconRoot.modelData.id
                    && panel.host.dragHoverScreen !== ""
                    && panel.host.dragHoverScreen !== panel.screenName) ? 0 : 1
          property real pressX: 0
          property real pressY: 0
          property real dragOffsetX: 0
          property real dragOffsetY: 0
          property real lastSceneX: 0
          property real lastSceneY: 0

          Binding on x {
            value: panel.posFor(iconRoot.modelData, iconRoot.index).x
            when: !iconMouse.drag.active
            restoreMode: Binding.RestoreNone
          }
          Binding on y {
            value: panel.posFor(iconRoot.modelData, iconRoot.index).y
            when: !iconMouse.drag.active
            restoreMode: Binding.RestoreNone
          }

          Rectangle {
            width: Math.max(panel.host.iconSize + 12,
                            Math.min(parent.width - 8, labelText.implicitWidth + 12))
            height: Math.min(parent.height - 8,
                             panel.host.iconSize + labelText.paintedHeight + 16)
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 8
            property bool selected: panel.host.isSelected(iconRoot.modelData.id) && emptyMouse.activeFocus
            color: selected ? Qt.rgba(1, 1, 1, 0.18) : (iconHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
            border.width: selected ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.35)
          }

          HoverHandler { id: iconHover }

          Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            Item {
              width: panel.host.iconSize
              height: panel.host.iconSize
              anchors.horizontalCenter: parent.horizontalCenter

              Image {
                id: fallbackGlyph
                anchors.fill: parent
                source: panel.host.fallbackIcon(iconRoot.modelData)
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                cache: false
                smooth: true
                visible: iconImage.status === Image.Error
                sourceSize.width: panel.host.iconIsRaster(source) ? panel.host.iconPixels : 0
                sourceSize.height: panel.host.iconIsRaster(source) ? panel.host.iconPixels : 0
              }

              Image {
                id: iconImage
                anchors.fill: parent
                source: panel.host.iconSource(iconRoot.modelData)
                fillMode: Image.PreserveAspectFit
                // Pop theme icons are SVG. Qt SVG is not thread-safe, so an
                // asynchronous decode often comes back blank while the label
                // still paints. A failed decode also poisons Image.cache.
                asynchronous: false
                cache: false
                smooth: true
                visible: status !== Image.Error
                sourceSize.width: panel.host.iconIsRaster(source) ? panel.host.iconPixels : 0
                sourceSize.height: panel.host.iconIsRaster(source) ? panel.host.iconPixels : 0
              }

              Rectangle {
                visible: panel.host.isUntrustedLauncher(iconRoot.modelData)
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 20
                height: 20
                radius: 10
                color: "#cc8a1515"
                border.width: 1
                border.color: "#eeffffff"

                Text {
                  anchors.centerIn: parent
                  text: "!"
                  textFormat: Text.PlainText
                  color: "white"
                  font.pixelSize: 13
                  font.bold: true
                  font.family: Style.fontFamily
                }
              }
            }

            Text {
              id: labelText
              visible: !panel.host.isRenamingItem(iconRoot.modelData, panel.screenName)
              width: parent.width
              text: panel.host.plainText(iconRoot.modelData.name)
              textFormat: Text.PlainText
              color: "white"
              style: Text.Outline
              styleColor: "#cc000000"
              font.pixelSize: 12
              font.family: Style.fontFamily
              wrapMode: Text.Wrap
              elide: Text.ElideRight
              maximumLineCount: 2
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Rectangle {
            visible: panel.host.isRenamingItem(iconRoot.modelData, panel.screenName)
            z: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 6
            height: 46
            radius: 4
            color: "#ee1a1a1a"
            border.width: 1
            border.color: "#88ffffff"

            TextInput {
              id: renameInput
              anchors.fill: parent
              anchors.margins: 4
              color: "white"
              font.pixelSize: 16
              font.family: Style.fontFamily
              wrapMode: TextInput.Wrap
              horizontalAlignment: TextInput.AlignHCenter
              verticalAlignment: TextInput.AlignVCenter
              selectByMouse: true
              clip: true
              maximumLength: 255
              property bool finishing: false
              property bool ready: false

              function commit() {
                if (finishing)
                  return
                finishing = true
                panel.host.commitRename(iconRoot.modelData, text)
              }

              function cancel() {
                if (finishing)
                  return
                finishing = true
                panel.host.cancelRename()
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  commit()
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  cancel()
                  event.accepted = true
                }
              }
              onVisibleChanged: {
                if (visible) {
                  finishing = false
                  ready = false
                  text = panel.host.plainText(iconRoot.modelData.name)
                  Qt.callLater(function() {
                    if (!panel.host.isRenamingItem(iconRoot.modelData, panel.screenName))
                      return
                    renameInput.forceActiveFocus()
                    renameInput.selectAll()
                    renameInput.ready = true
                  })
                } else {
                  ready = false
                }
              }
              onActiveFocusChanged: {
                if (visible && ready && !activeFocus)
                  commit()
              }
            }
          }

          MouseArea {
            id: iconMouse
            anchors.fill: parent
            z: 2
            enabled: !panel.host.isRenamingItem(iconRoot.modelData, panel.screenName)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            drag.target: iconRoot
            drag.axis: Drag.XAndYAxis
            drag.threshold: 8
            // Do not clamp the dragged item to this output. The pointer grab
            // must be allowed to cross the virtual desktop so the release
            // handler can transfer the item to the other output.
            drag.minimumX: -panel.width * 2
            drag.minimumY: -panel.height * 2
            drag.maximumX: panel.width * 2
            drag.maximumY: panel.height * 2
            onPressed: function(mouse) {
              iconRoot.pressX = iconRoot.x
              iconRoot.pressY = iconRoot.y
              iconRoot.dragOffsetX = mouse.x
              iconRoot.dragOffsetY = mouse.y
              iconRoot.lastSceneX = panel.modelData.x + iconRoot.x + mouse.x
              iconRoot.lastSceneY = panel.modelData.y + iconRoot.y + mouse.y
              panel.host.selectItem(iconRoot.modelData, mouse.modifiers)
              emptyMouse.forceActiveFocus()
              if (mouse.button === Qt.LeftButton)
                panel.host.beginDrag(
                  iconRoot.modelData, panel.screenName,
                  iconRoot.lastSceneX, iconRoot.lastSceneY, mouse.x, mouse.y
                )
            }
            onPositionChanged: function(mouse) {
              if (!(mouse.buttons & Qt.LeftButton))
                return
              iconRoot.lastSceneX = panel.modelData.x + iconRoot.x + mouse.x
              iconRoot.lastSceneY = panel.modelData.y + iconRoot.y + mouse.y
              panel.host.updateDragPointer(iconRoot.lastSceneX, iconRoot.lastSceneY)
            }
            onCanceled: panel.host.clearDrag()
            onReleased: function(mouse) {
              if (mouse.button !== Qt.LeftButton) {
                panel.host.clearDrag()
                return
              }
              var itemId = iconRoot.modelData.id
              var fromScreen = panel.screenName
              var sceneX = iconRoot.lastSceneX
              var sceneY = iconRoot.lastSceneY
              var grabX = iconRoot.dragOffsetX
              var grabY = iconRoot.dragOffsetY
              var pressX = iconRoot.pressX
              var pressY = iconRoot.pressY
              var dropX = iconRoot.x
              var dropY = iconRoot.y
              var wasDragged = Math.abs(dropX - pressX) > 8
                || Math.abs(dropY - pressY) > 8
              // Hide the follow-cursor ghost before any layout change.
              // moveItemToScreen removes this id from the source screen, which
              // destroys this delegate and would skip a clearDrag() after it.
              panel.host.clearDrag()
              if (!wasDragged)
                return
              var targetScreen = panel.host.screenAtPoint(sceneX, sceneY)
              if (targetScreen && String(targetScreen.name || "default") !== fromScreen
                  && Quickshell.screens.length > 1) {
                panel.host.moveItemToScreen(
                  itemId,
                  fromScreen,
                  String(targetScreen.name || "default"),
                  sceneX - targetScreen.x - grabX,
                  sceneY - targetScreen.y - grabY
                )
                return
              }
              var target = panel.itemAt(
                dropX + iconRoot.width / 2,
                dropY + iconRoot.height / 2,
                itemId
              )
              if (target && panel.host.isTrash(target) && !panel.host.isTrash(iconRoot.modelData)) {
                panel.host.trashItem(iconRoot.modelData)
                return
              }
              var snapped = panel.snap(dropX, dropY)
              var grid = panel.host.gridFor(panel.modelData)
              var sourceCell = DesktopLayout.cellFromPixel(pressX, pressY, grid)
              var targetCell = DesktopLayout.cellFromPixel(snapped.x, snapped.y, grid)
              iconRoot.x = snapped.x
              iconRoot.y = snapped.y
              panel.host.moveItemWithinScreen(
                fromScreen, itemId, sourceCell, targetCell
              )
            }
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) {
                if (!panel.host.isSelected(iconRoot.modelData.id))
                  panel.host.selectItem(iconRoot.modelData, 0)
                panel.openItemMenu(iconRoot.modelData, iconRoot, mouse)
                return
              }
              if (iconMouse.drag.active) return
              if (Math.abs(iconRoot.x - iconRoot.pressX) > 8 || Math.abs(iconRoot.y - iconRoot.pressY) > 8)
                return
              panel.closeMenu()
            }
            onDoubleClicked: function(mouse) {
              if (mouse.button !== Qt.LeftButton || iconMouse.drag.active)
                return
              panel.closeMenu()
              panel.host.openOrConfirm(iconRoot.modelData, panel.screenName)
            }
          }

          DropArea {
            anchors.fill: parent
            z: 3
            enabled: panel.host.isTrash(iconRoot.modelData)
            keys: ["text/uri-list"]
            onEntered: panel.dropping = true
            onExited: panel.dropping = false
            onDropped: function(drop) {
              panel.dropping = false
              if (!panel.host.isTrash(iconRoot.modelData))
                return
              var urls = []
              if (drop.urls) {
                for (var i = 0; i < drop.urls.length; i++)
                  urls.push(String(drop.urls[i]))
              }
              if (urls.length > 0) {
                drop.acceptProposedAction()
                panel.host.trashUrls(urls)
              }
            }
          }
        }
      }

        Rectangle {
        id: menuBox
        visible: menuKind !== ""
        z: 20
        width: menuCol.implicitWidth + 16
        height: menuCol.implicitHeight + 12
        radius: 8
        color: Color.popups.background
        border.width: 1
        border.color: Color.popups.border
        x: Math.min(Math.max(8, menuX), Math.max(8, panel.width - width - 8))
        y: Math.min(Math.max(8, menuY), Math.max(8, panel.height - height - 8))

        // Bind plugin state onto this item so menu JS never needs the `panel` id.
        property var pluginHost: host
        property var currentItem: menuItem
        property string currentScreen: panel.screenName
        property int closeTick: 0

        function activateMenu(action) {
          var item = currentItem
          var plugin = pluginHost
          var screenName = currentScreen
          closeTick += 1
          if (!plugin)
            return
          if (action === "open")
            plugin.openOrConfirm(item, screenName)
          else if (action === "trust")
            plugin.allowLaunching(item)
          else if (action === "trust-open")
            plugin.trustAndOpen(item)
          else if (action === "trash")
            plugin.trashItem(item)
          else if (action === "rename")
            plugin.beginRename(item, screenName)
          else if (action === "folder")
            plugin.newFolder()
          else if (action === "shortcut")
            plugin.newShortcut()
          else if (action === "pin")
            plugin.pinApp()
          else if (action === "addfiles")
            plugin.addFiles()
          else if (action === "refresh")
            plugin.refresh()
          else if (action === "files") {
            if (item && item.path)
              plugin.revealItem(item)
            else
              plugin.openDesktopFolder()
          }
        }

        Column {
          id: menuCol
          anchors.centerIn: parent
          width: Math.max(188, implicitWidth)
          spacing: 2

          Repeater {
            model: menuEntries

            Rectangle {
              width: menuCol.width
              height: 28
              radius: 4
              color: rowMouse.containsMouse ? Util.alpha(Color.popups.text, 0.12) : "transparent"

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
                text: String(modelData.label || "")
                textFormat: Text.PlainText
                color: Color.popups.text
                font.pixelSize: 13
                font.family: Style.fontFamily
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: function(mouse) {
                  var action = String(modelData.action || "")
                  var node = rowMouse
                  while (node) {
                    if (typeof node.activateMenu === "function") {
                      node.activateMenu(action)
                      return
                    }
                    node = node.parent
                  }
                }
              }
            }
          }
        }
      }

      Connections {
        target: menuBox
        function onCloseTickChanged() {
          menuKind = ""
          menuItem = null
        }
      }

      Connections {
        target: host
        function onItemsChanged() {
          panel.refreshVisibleItems()
          panel.maybeRepack()
        }
        function onLayoutStateChanged() {
          panel.refreshVisibleItems()
        }
        function onScreenTopologyChanged() {
          host.reconcileLayout()
          panel.refreshVisibleItems()
          panel.maybeRepack()
        }
      }

      Component.onCompleted: panel.refreshVisibleItems()

      Rectangle {
        id: trustBox
        visible: {
          var item = host.pendingTrust
          if (!item)
            return false
          if (host.pendingTrustScreen && host.pendingTrustScreen !== panel.screenName)
            return false
          return true
        }
        z: 21
        width: Math.min(360, Math.max(280, panel.width - 48))
        height: trustCol.implicitHeight + 24
        radius: 8
        color: Color.popups.background
        border.width: 1
        border.color: Color.popups.border
        x: {
          var p = panel.trustIconPos()
          if (!p)
            return Math.max(8, Math.round(panel.width / 2 - width / 2))
          return Math.min(Math.max(8, Math.round(p.x + host.cellW / 2 - width / 2)),
                          Math.max(8, panel.width - width - 8))
        }
        y: {
          var p = panel.trustIconPos()
          if (!p)
            return Math.max(8, Math.round(panel.height / 2 - height / 2))
          var above = p.y - height - 8
          if (above >= 8)
            return above
          return p.y + host.cellH + 8
        }

        MouseArea {
          anchors.fill: parent
          onClicked: {}
        }

        Column {
          id: trustCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 12
          spacing: 10

          Text {
            width: parent.width
            text: "Untrusted launcher"
            textFormat: Text.PlainText
            color: Color.popups.text
            font.pixelSize: 15
            font.bold: true
            font.family: Style.fontFamily
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: {
              var item = host.pendingTrust
              var label = item ? (item.id || item.name || "this shortcut") : "this shortcut"
              return "\"" + host.plainText(label, 80) + "\" is not marked as trusted. Opening it will run commands from the file."
            }
            textFormat: Text.PlainText
            color: Color.popups.text
            font.pixelSize: 13
            font.family: Style.fontFamily
            wrapMode: Text.WordWrap
          }

          Row {
            anchors.right: parent.right
            spacing: 8

            Rectangle {
              width: cancelLabel.implicitWidth + 20
              height: 28
              radius: 4
              color: cancelMouse.containsMouse ? Util.alpha(Color.popups.text, 0.12) : "transparent"
              border.width: 1
              border.color: Color.popups.border

              Text {
                id: cancelLabel
                anchors.centerIn: parent
                text: "Cancel"
                textFormat: Text.PlainText
                color: Color.popups.text
                font.pixelSize: 13
                font.family: Style.fontFamily
              }

              MouseArea {
                id: cancelMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: host.clearTrustPrompt()
              }
            }

            Rectangle {
              width: trustLabel.implicitWidth + 20
              height: 28
              radius: 4
              color: trustMouse.containsMouse ? Util.alpha(Color.popups.text, 0.12) : Qt.rgba(1, 1, 1, 0.08)
              border.width: 1
              border.color: Color.popups.border

              Text {
                id: trustLabel
                anchors.centerIn: parent
                text: "Trust and Open"
                textFormat: Text.PlainText
                color: Color.popups.text
                font.pixelSize: 13
                font.family: Style.fontFamily
              }

              MouseArea {
                id: trustMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: host.trustAndOpen(host.pendingTrust)
              }
            }
          }
        }
        }
      }
    }
  }
}
