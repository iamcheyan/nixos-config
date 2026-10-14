.pragma library

// Pure helpers for the Labwc dock. The QML host owns state; this file only
// turns toplevels and pins into a stable per-output app list.

function stripDesktop(id) {
  return String(id == null ? "" : id).replace(/\.desktop$/i, "")
}

function iconIsRaster(url) {
  var src = String(url || "").toLowerCase().split("?")[0]
  return !(src.endsWith(".svg") || src.endsWith(".svgz"))
}

function windowOnScreen(win, screen, activeTl) {
  if (!win) return false
  var screens = win.screens || []
  if (screens.length === 0) return win === activeTl
  var screenName = screen && screen.name ? String(screen.name) : ""
  for (var i = 0; i < screens.length; i++) {
    if (screens[i] === screen) return true
    if (screenName && String(screens[i].name || "") === screenName) return true
  }
  return false
}

function windowListMatch(a, b) {
  if (a === b) return true
  if (!a || !b || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false
  }
  return true
}

function fieldsMatch(a, b) {
  return !!(a && b
    && a.id === b.id
    && a.name === b.name
    && a.icon === b.icon
    && a.isPinned === b.isPinned
    && a.isRunning === b.isRunning
    && a.isActive === b.isActive
    && a.isSeparatorBefore === b.isSeparatorBefore
    && windowListMatch(a.windows, b.windows))
}

function listsMatch(current, next) {
  if (current === next) return true
  if (!current || !next || current.length !== next.length) return false
  for (var i = 0; i < current.length; i++) {
    if (!fieldsMatch(current[i], next[i])) return false
  }
  return true
}

function containsApp(list, appId) {
  for (var i = 0; i < (list || []).length; i++) {
    if (list[i] && list[i].id === appId) return true
  }
  return false
}

function moveItem(list, from, to) {
  if (!Array.isArray(list)) return []
  var len = list.length
  if (from < 0 || to < 0 || from >= len || to >= len) return list.slice()
  if (from === to) return list.slice()
  var next = list.slice()
  var item = next.splice(from, 1)[0]
  next.splice(to, 0, item)
  return next
}

function sameIdList(a, b) {
  if (a === b) return true
  if (!a || !b || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    if (stripDesktop(a[i]) !== stripDesktop(b[i])) return false
  }
  return true
}

function uniqueIds(ids) {
  var out = []
  var seen = {}
  for (var i = 0; i < (ids || []).length; i++) {
    var id = stripDesktop(ids[i])
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

// After a drag, persist a mixed visual order. Trailing unpinned running apps
// stay unpinned when the user only rearranged already-pinned items. Anything
// that ends up between kept items (old pins + the dragged id) is pinned so a
// running app dropped into the dock body keeps its slot.
function pinnedFromVisual(visualIds, draggedId, previousPinned) {
  var visual = uniqueIds(visualIds)
  var prev = uniqueIds(previousPinned)
  if (visual.length === 0) return prev
  if (prev.length === 0) return visual

  var keep = {}
  for (var i = 0; i < prev.length; i++) keep[prev[i]] = true
  var dragged = stripDesktop(draggedId)
  if (dragged) keep[dragged] = true

  var firstKeep = -1
  var lastKeep = -1
  for (var j = 0; j < visual.length; j++) {
    if (keep[visual[j]]) {
      if (firstKeep < 0) firstKeep = j
      lastKeep = j
    }
  }
  if (firstKeep < 0) return prev
  return visual.slice(firstKeep, lastKeep + 1)
}

function buildApps(opts) {
  var pinned = opts && opts.pinnedApps ? opts.pinnedApps : []
  var toplevels = opts && opts.toplevels ? opts.toplevels : []
  var screen = opts ? opts.screen : null
  var activeTl = opts ? opts.activeToplevel : null
  var nameFor = opts && opts.nameFor ? opts.nameFor : function(id) { return id }
  var iconFor = opts && opts.iconFor ? opts.iconFor : function() { return "" }

  var runningMap = {}
  for (var i = 0; i < toplevels.length; i++) {
    var win = toplevels[i]
    if (!win) continue
    var cleanId = stripDesktop(win.appId || win.initialAppId || win.title || "application")
    if (!runningMap[cleanId])
      runningMap[cleanId] = { id: cleanId, windows: [] }
    if (windowOnScreen(win, screen, activeTl))
      runningMap[cleanId].windows.push(win)
  }

  var list = []
  var added = {}
  for (var p = 0; p < pinned.length; p++) {
    var pId = stripDesktop(pinned[p])
    if (!pId || added[pId]) continue
    var running = runningMap[pId]
    var wins = running ? running.windows : []
    list.push({
      id: pId,
      name: nameFor(pId),
      icon: iconFor(pId),
      isPinned: true,
      isRunning: wins.length > 0,
      windows: wins,
      isActive: wins.some(function(w) { return w.activated }),
      isSeparatorBefore: false
    })
    added[pId] = true
  }

  var firstUnpinned = true
  for (var rId in runningMap) {
    if (added[rId]) continue
    var rData = runningMap[rId]
    if (rData.windows.length === 0) continue
    list.push({
      id: rId,
      name: nameFor(rId),
      icon: iconFor(rId),
      isPinned: false,
      isRunning: true,
      windows: rData.windows,
      isActive: rData.windows.some(function(w) { return w.activated }),
      isSeparatorBefore: firstUnpinned && list.length > 0
    })
    firstUnpinned = false
  }

  return list
}
