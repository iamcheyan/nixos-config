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

function gridRows(grid) {
  var rows = grid && grid.rows
  return rows > 0 ? Math.floor(rows) : 1
}

function gridCols(grid) {
  var cols = grid && grid.cols
  return cols > 0 ? Math.floor(cols) : 32
}

function clampCell(cell, grid) {
  var col = cell && cell.col !== undefined ? Math.floor(cell.col) : 0
  var row = cell && cell.row !== undefined ? Math.floor(cell.row) : 0
  return {
    col: Math.max(0, Math.min(gridCols(grid) - 1, col)),
    row: Math.max(0, Math.min(gridRows(grid) - 1, row))
  }
}

function cellFromPixel(x, y, grid) {
  return clampCell({
    col: Math.round((x - grid.left) / grid.cellW),
    row: Math.round((y - grid.top) / grid.cellH)
  }, grid)
}

function pixelFromCell(cell, grid) {
  var clamped = clampCell(cell, grid)
  return {
    x: grid.left + clamped.col * grid.cellW,
    y: grid.top + clamped.row * grid.cellH
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

function gridFor(grids, screen) {
  if (grids && grids[screen] && grids[screen].rows)
    return grids[screen]
  if (grids && grids.default && grids.default.rows)
    return grids.default
  return grids
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

function occupiedFrom(entries) {
  var occupied = {}
  for (var id in entries || {}) {
    var cell = entries[id]
    if (cell && cell.col !== undefined && cell.row !== undefined)
      occupied[cellKey(cell.col, cell.row)] = id
  }
  return occupied
}

function migrate(raw, ids, screens, grids) {
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
            state.screens[screen][id] = cellFromPixel(
              point.x, point.y, gridFor(grids, screen)
            )
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
    var newId = ids[missing]
    if (assigned[newId])
      continue
    var target = screens[missing % screens.length]
    var targetGrid = gridFor(grids, target)
    if (!state.screens[target])
      state.screens[target] = {}
    var occupied = occupiedFrom(state.screens[target])
    var free = firstFree(occupied, targetGrid, 0)
    state.screens[target][newId] = free
    assigned[newId] = target
  }

  for (var current = 0; current < screens.length; current++) {
    if (!state.screens[screens[current]])
      state.screens[screens[current]] = {}
  }
  return state
}

function normalize(raw, items, screenNames, grids) {
  var ids = itemIds(items)
  var screens = screenNamesFrom(screenNames)
  var state = migrate(raw, ids, screens, grids)
  repair(state, screens, grids)
  return state
}

function repair(state, activeScreens, grids) {
  for (var screen in state.screens) {
    var grid = gridFor(grids, screen)
    var entries = state.screens[screen] || {}
    var occupied = {}
    var overflow = []
    for (var id in entries) {
      var cell = clampCell(entries[id], grid)
      var key = cellKey(cell.col, cell.row)
      if (occupied[key]) {
        overflow.push(id)
        delete entries[id]
      } else {
        entries[id] = cell
        occupied[key] = id
      }
    }
    for (var i = 0; i < overflow.length; i++) {
      var free = firstFree(occupied, grid, 0)
      entries[overflow[i]] = free
      occupied[cellKey(free.col, free.row)] = overflow[i]
    }
  }

  return state
}

function firstFree(occupied, grid, start) {
  var rows = gridRows(grid)
  var cols = gridCols(grid)
  var capacity = Math.max(1, rows * cols)
  var index = Math.max(0, start || 0) % capacity
  for (var n = 0; n < capacity; n++) {
    var i = (index + n) % capacity
    var cell = { col: Math.floor(i / rows), row: i % rows }
    if (!occupied[cellKey(cell.col, cell.row)])
      return cell
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

function cellMap(state, ids, screenName, grid) {
  var map = {}
  var occupied = {}
  var entries = state && isObject(state.screens) ? (state.screens[screenName] || {}) : {}
  var overflow = []
  for (var i = 0; i < (ids || []).length; i++) {
    var id = String(ids[i] || "")
    if (!id)
      continue
    if (entries[id]) {
      var cell = clampCell(entries[id], grid)
      var key = cellKey(cell.col, cell.row)
      if (occupied[key])
        overflow.push(id)
      else {
        map[id] = cell
        occupied[key] = id
      }
    } else {
      overflow.push(id)
    }
  }
  for (var j = 0; j < overflow.length; j++) {
    var guest = overflow[j]
    var free = firstFree(occupied, grid, 0)
    map[guest] = free
    occupied[cellKey(free.col, free.row)] = guest
  }
  return map
}

function position(state, screenName, id, fallbackIndex, grid) {
  var entries = state && isObject(state.screens) ? (state.screens[screenName] || {}) : {}
  if (entries[id])
    return pixelFromCell(entries[id], grid)
  return pixelFromCell({
    col: Math.floor(fallbackIndex / gridRows(grid)),
    row: fallbackIndex % gridRows(grid)
  }, grid)
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

// Move a set of icons as a rigid grid group. A group move is rejected when
// any destination cell is occupied by an icon outside the group, preventing
// partial moves and overlaps.
function moveGroup(state, fromScreen, toScreen, moves, grid) {
  var next = clone(state)
  var targetEntries = next.screens[toScreen] || {}
  var moving = {}
  var destinations = {}

  for (var i = 0; i < moves.length; i++) {
    var move = moves[i]
    var target = grid ? clampCell(move.targetCell, grid) : {
      col: move.targetCell.col,
      row: move.targetCell.row
    }
    var destKey = cellKey(target.col, target.row)
    if (destinations[destKey])
      return clone(state)
    moving[String(move.id)] = true
    destinations[destKey] = true
    move.targetCell = target
  }

  for (var targetId in targetEntries) {
    var occupant = targetEntries[targetId]
    if (!moving[targetId] && destinations[cellKey(occupant.col, occupant.row)])
      return clone(state)
  }

  for (var j = 0; j < moves.length; j++) {
    var currentId = String(moves[j].id)
    for (var screen in next.screens) {
      if (next.screens[screen])
        delete next.screens[screen][currentId]
    }
  }
  if (!next.screens[toScreen])
    next.screens[toScreen] = {}

  for (var k = 0; k < moves.length; k++) {
    var current = moves[k]
    next.screens[toScreen][String(current.id)] = {
      col: current.targetCell.col,
      row: current.targetCell.row
    }
  }
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
  if (targetId && targetId !== id) {
    if (fromScreen !== toScreen) {
      // A cross-screen drop swaps ownership as well as position. The target
      // icon must return to the source screen, where the dragged icon came
      // from; source coordinates are grid cells for that screen.
      delete next.screens[toScreen][targetId]
      if (!next.screens[fromScreen])
        next.screens[fromScreen] = {}
      next.screens[fromScreen][targetId] = sourceCell
    } else {
      next.screens[toScreen][targetId] = sourceCell
    }
  }
  next.screens[toScreen][id] = { col: targetCell.col, row: targetCell.row }
  return next
}
