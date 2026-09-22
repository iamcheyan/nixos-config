.pragma library

// Pure desktop layout model. Coordinates are persisted as grid cells, not
// pixels, so icon size, scale, and monitor geometry can change independently.

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function empty() {
  return { version: 3, screens: {} }
}

function cellKey(col, row) {
  return String(col) + "," + String(row)
}

function cellFromPixel(x, y, grid) {
  return {
    col: Math.max(0, Math.round((x - grid.left) / grid.cellW)),
    row: Math.max(0, Math.round((y - grid.top) / grid.cellH))
  }
}

function pixelFromCell(cell, grid) {
  return {
    x: grid.left + Math.max(0, cell.col) * grid.cellW,
    y: grid.top + Math.max(0, cell.row) * grid.cellH
  }
}

function isObject(value) {
  return value && typeof value === "object" && !Array.isArray(value)
}

function screenNamesFrom(value) {
  var result = []
  for (var i = 0; i < (value || []).length; i++) {
    var name = String(value[i] || "")
    if (name && result.indexOf(name) < 0)
      result.push(name)
  }
  return result.length > 0 ? result : ["default"]
}

function itemIds(items) {
  var result = []
  for (var i = 0; i < (items || []).length; i++) {
    var id = String(items[i].id || "")
    if (id && result.indexOf(id) < 0)
      result.push(id)
  }
  return result
}

function homeOf(state, id) {
  var savedScreens = state && isObject(state.screens) ? state.screens : {}
  for (var screen in savedScreens) {
    if (savedScreens[screen] && savedScreens[screen][id])
      return screen
  }
  return ""
}

function migrate(raw, ids, screens, grid) {
  var state = empty()
  var source = raw || {}
  if (source.version === 3 && isObject(source.screens))
    state.screens = clone(source.screens)
  else {
    var positions = isObject(source.positions) ? source.positions : source
    if (isObject(positions)) {
      for (var screen in positions) {
        if (!isObject(positions[screen]))
          continue
        state.screens[screen] = {}
        for (var id in positions[screen]) {
          var point = positions[screen][id]
          if (point && point.x !== undefined && point.y !== undefined)
            state.screens[screen][id] = cellFromPixel(point.x, point.y, grid)
        }
      }
    }
  }

  var valid = {}
  for (var i = 0; i < ids.length; i++)
    valid[ids[i]] = true

  for (var oldScreen in state.screens) {
    if (!isObject(state.screens[oldScreen])) {
      delete state.screens[oldScreen]
      continue
    }
    for (var oldId in state.screens[oldScreen]) {
      var cell = state.screens[oldScreen][oldId]
      if (!valid[oldId] || !cell || cell.col === undefined || cell.row === undefined)
        delete state.screens[oldScreen][oldId]
    }
  }

  var assigned = {}
  for (var existingScreen in state.screens) {
    for (var existingId in state.screens[existingScreen]) {
      if (!assigned[existingId])
        assigned[existingId] = existingScreen
      else
        delete state.screens[existingScreen][existingId]
    }
  }

  for (var missing = 0; missing < ids.length; missing++) {
    var id = ids[missing]
    if (assigned[id])
      continue
    var target = screens[missing % screens.length]
    if (!state.screens[target])
      state.screens[target] = {}
    state.screens[target][id] = {
      col: Math.floor(missing / Math.max(1, grid.rows)),
      row: missing % Math.max(1, grid.rows)
    }
    assigned[id] = target
  }

  for (var current = 0; current < screens.length; current++) {
    if (!state.screens[screens[current]])
      state.screens[screens[current]] = {}
  }
  return state
}

function normalize(raw, items, screenNames, grid) {
  var ids = itemIds(items)
  var screens = screenNamesFrom(screenNames)
  var state = migrate(raw, ids, screens, grid)
  repair(state, screens, grid)
  return state
}

function repair(state, activeScreens, grid) {
  var screens = screenNamesFrom(activeScreens)
  for (var screen in state.screens) {
    var cells = {}
    var duplicates = []
    var entries = state.screens[screen] || {}
    for (var id in entries) {
      var cell = entries[id]
      var key = cellKey(cell.col, cell.row)
      if (cells[key]) {
        duplicates.push(id)
        delete entries[id]
      } else {
        cells[key] = id
      }
    }
    for (var i = 0; i < duplicates.length; i++) {
      var free = firstFree(cells, grid, i)
      entries[duplicates[i]] = free
      cells[cellKey(free.col, free.row)] = duplicates[i]
    }
  }

  return state
}

function firstFree(occupied, grid, start) {
  var index = Math.max(0, start || 0)
  var limit = 4096
  while (limit-- > 0) {
    var cell = { col: Math.floor(index / grid.rows), row: index % grid.rows }
    if (!occupied[cellKey(cell.col, cell.row)])
      return cell
    index++
  }
  return { col: 0, row: 0 }
}

function visibleIds(state, items, activeScreens, screenName) {
  var ids = itemIds(items)
  var screens = screenNamesFrom(activeScreens)
  if (screens.length <= 1)
    return ids
  var active = {}
  for (var i = 0; i < screens.length; i++)
    active[screens[i]] = true
  var result = []
  for (var j = 0; j < ids.length; j++) {
    var home = homeOf(state, ids[j])
    if (home === screenName || (!active[home] && screenName === screens[0]))
      result.push(ids[j])
  }
  return result
}

function position(state, screenName, id, fallbackIndex, grid) {
  var entries = state && isObject(state.screens) ? (state.screens[screenName] || {}) : {}
  if (entries[id])
    return pixelFromCell(entries[id], grid)
  return pixelFromCell({ col: Math.floor(fallbackIndex / grid.rows), row: fallbackIndex % grid.rows }, grid)
}

function moveOrSwap(state, screenName, id, sourceCell, targetCell) {
  var next = clone(state)
  if (!next.screens[screenName])
    next.screens[screenName] = {}
  var entries = next.screens[screenName]
  var targetId = ""
  for (var otherId in entries) {
    if (otherId !== id && entries[otherId].col === targetCell.col && entries[otherId].row === targetCell.row) {
      targetId = otherId
      break
    }
  }
  if (targetId)
    entries[targetId] = { col: sourceCell.col, row: sourceCell.row }
  entries[id] = { col: targetCell.col, row: targetCell.row }
  return next
}

function moveToScreen(state, id, fromScreen, toScreen, targetCell) {
  var next = clone(state)
  var sourceCell = null
  if (next.screens[fromScreen] && next.screens[fromScreen][id])
    sourceCell = next.screens[fromScreen][id]
  if (!sourceCell) {
    var home = homeOf(next, id)
    if (home && next.screens[home] && next.screens[home][id]) {
      sourceCell = next.screens[home][id]
      fromScreen = home
    }
  }
  if (!sourceCell)
    sourceCell = { col: 0, row: 0 }
  if (next.screens[fromScreen])
    delete next.screens[fromScreen][id]
  if (!next.screens[toScreen])
    next.screens[toScreen] = {}
  var targetId = ""
  for (var otherId in next.screens[toScreen]) {
    if (next.screens[toScreen][otherId].col === targetCell.col
        && next.screens[toScreen][otherId].row === targetCell.row) {
      targetId = otherId
      break
    }
  }
  if (targetId)
    next.screens[toScreen][targetId] = sourceCell
  next.screens[toScreen][id] = { col: targetCell.col, row: targetCell.row }
  return next
}
