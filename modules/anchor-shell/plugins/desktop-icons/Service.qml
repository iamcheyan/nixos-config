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
  property int padBottom: 24
  readonly property int maxItems: 256
  readonly property int maxListChars: 262144
  readonly property int maxNameLength: 120
  property var pendingTrust: null
  property string pendingTrustScreen: ""
  property string renamingId: ""
  property string renamingScreen: ""
  property bool renameBusy: false
  property string lastWrittenPositions: ""
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
    : (anchorConfigDir + "/plugins/desktop-icons")
  readonly property string indexScript: pluginDir + "/bin/desktop-index"
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
      root.gridsForScreens()
    )
  }

  function gridsForScreens() {
    var grids = {}
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      grids[String(screen.name || "default")] = root.gridFor(screen)
    }
    if (Object.keys(grids).length === 0)
      grids.default = root.gridFor(null)
    return grids
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

  function scheduleRefresh() {
    refreshDebounce.restart()
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
      Quickshell.execDetached(["dolphin", "--select", item.path])
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
    var canonical = root.canonicalPositions(raw)
    if (root.lastWrittenPositions && canonical === root.lastWrittenPositions)
      return
    root.lastWrittenPositions = ""
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
    var text = JSON.stringify(root.layoutState || DesktopLayout.empty(), null, 2) + "\n"
    root.lastWrittenPositions = root.canonicalPositions(text)
    posFile.setText(text)
  }

  function canonicalPositions(raw) {
    try {
      return JSON.stringify(JSON.parse(String(raw || "{}")))
    } catch (e) {
      return String(raw || "")
    }
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
    onFileChanged: reload()
  }

  // Watch the Desktop folder itself so icons appear, move, or get deleted
  // immediately instead of waiting for the fallback poll below.
  FileView {
    id: desktopWatch
    path: root.desktopPath
    watchChanges: true
    printErrors: false
    onLoaded: root.scheduleRefresh()
    onFileChanged: root.scheduleRefresh()
    onLoadFailed: root.scheduleRefresh()
  }

  // Coalesce the burst of events produced by a copy, rename, or trash move.
  Timer {
    id: refreshDebounce
    interval: 100
    repeat: false
    onTriggered: root.refresh()
  }

  // Safety-net poll. The directory watch above handles the common case
  // instantly; this keeps add/delete reliable if the watch ever misses.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  Variants {
    model: Quickshell.screens

    DesktopSurface {
      host: root
    }
  }
}
