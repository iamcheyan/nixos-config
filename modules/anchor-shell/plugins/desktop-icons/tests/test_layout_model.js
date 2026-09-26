const assert = require("assert")
const fs = require("fs")
const vm = require("vm")

const sourcePath = `${__dirname}/../DesktopLayout.js`
const source = fs.readFileSync(sourcePath, "utf8")
  .replace(/^\.pragma library\s*/, "")
  + `\nthis.layout = {\n`
  + [
    "empty", "cellFromPixel", "pixelFromCell", "homeOf", "normalize",
    "repair", "visibleIds", "position", "moveOrSwap", "moveToScreen", "moveGroup",
    "clampCell", "cellMap", "firstFree"
  ].map(name => `${name},`).join("\n")
  + "}\n"

const context = { Math, JSON, String, Number, Object, Array }
vm.createContext(context)
vm.runInContext(source, context, { filename: sourcePath })
const layout = context.layout
const grid = { left: 24, top: 48, cellW: 96, cellH: 104, rows: 5, cols: 8 }
const grids = {
  HDMI1: grid,
  HDMI2: { left: 32, top: 64, cellW: 96, cellH: 104, rows: 8, cols: 12 }
}
const items = [{ id: "a" }, { id: "b" }, { id: "c" }]
const equalJson = (actual, expected) =>
  assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected))

let state = layout.normalize(
  { version: 3, screens: { HDMI1: { a: { col: 0, row: 0 }, b: { col: 0, row: 0 } } } },
  items,
  ["HDMI1", "HDMI2"],
  grids
)
assert.notStrictEqual(state.screens.HDMI1.a.col + "," + state.screens.HDMI1.a.row,
  state.screens.HDMI1.b.col + "," + state.screens.HDMI1.b.row)
assert.strictEqual(layout.homeOf(state, "c"), "HDMI1")

state = layout.normalize(
  { version: 3, screens: { HDMI1: {
    a: { col: 0, row: 0 },
    b: { col: 0, row: 1 },
    c: { col: 0, row: 2 }
  } } },
  items,
  ["HDMI1", "HDMI2"],
  grids
)
const swapped = layout.moveOrSwap(
  state, "HDMI1", "a", { col: 0, row: 0 }, { col: 0, row: 1 }
)
equalJson(swapped.screens.HDMI1.a, { col: 0, row: 1 })
equalJson(swapped.screens.HDMI1.b, { col: 0, row: 0 })

const moved = layout.moveToScreen(
  swapped, "a", "HDMI1", "HDMI2", { col: 1, row: 1 }
)
assert.strictEqual(layout.homeOf(moved, "a"), "HDMI2")
assert.strictEqual(layout.homeOf(moved, "b"), "HDMI1")
equalJson(moved.screens.HDMI2.a, { col: 1, row: 1 })

const crossScreenSwap = layout.moveToScreen(
  moved, "a", "HDMI2", "HDMI1", { col: 0, row: 0 }
)
assert.strictEqual(layout.homeOf(crossScreenSwap, "a"), "HDMI1")
assert.strictEqual(layout.homeOf(crossScreenSwap, "b"), "HDMI2")
equalJson(crossScreenSwap.screens.HDMI1.a, { col: 0, row: 0 })
equalJson(crossScreenSwap.screens.HDMI2.b, { col: 1, row: 1 })

const crossScreenEmpty = layout.moveToScreen(
  crossScreenSwap, "b", "HDMI2", "HDMI1", { col: 2, row: 2 }
)
assert.strictEqual(layout.homeOf(crossScreenEmpty, "b"), "HDMI1")
equalJson(crossScreenEmpty.screens.HDMI1.b, { col: 2, row: 2 })

const sameScreenMove = layout.moveToScreen(
  crossScreenEmpty, "b", "HDMI1", "HDMI1", { col: 0, row: 0 }
)
equalJson(sameScreenMove.screens.HDMI1.b, { col: 0, row: 0 })

const groupState = layout.normalize(
  { version: 3, screens: { HDMI1: {
    a: { col: 0, row: 0 },
    b: { col: 1, row: 0 },
    c: { col: 3, row: 0 }
  } } },
  items,
  ["HDMI1", "HDMI2"],
  grids
)
const movedGroup = layout.moveGroup(groupState, "HDMI1", "HDMI2", [
  { id: "a", targetCell: { col: 0, row: 1 } },
  { id: "b", targetCell: { col: 1, row: 1 } }
])
assert.strictEqual(layout.homeOf(movedGroup, "a"), "HDMI2")
assert.strictEqual(layout.homeOf(movedGroup, "b"), "HDMI2")
equalJson(movedGroup.screens.HDMI2.a, { col: 0, row: 1 })
equalJson(movedGroup.screens.HDMI2.b, { col: 1, row: 1 })
assert.strictEqual(layout.homeOf(movedGroup, "c"), "HDMI1")

const blockedGroup = layout.moveGroup(groupState, "HDMI1", "HDMI1", [
  { id: "a", targetCell: { col: 0, row: 2 } },
  { id: "b", targetCell: { col: 3, row: 0 } }
])
equalJson(blockedGroup, groupState)

equalJson(layout.cellFromPixel(120, 160, grid), { col: 1, row: 1 })
equalJson(layout.pixelFromCell({ col: 1, row: 1 }, grid), { x: 120, y: 152 })

const perScreen = layout.normalize(
  {},
  items,
  ["HDMI1", "HDMI2"],
  grids
)
equalJson(perScreen.screens.HDMI2.b, { col: 0, row: 0 })

const migrated = layout.normalize(
  { positions: { HDMI2: { a: { x: 32, y: 168 } } } },
  [{ id: "a" }],
  ["HDMI1", "HDMI2"],
  grids
)
equalJson(migrated.screens.HDMI2.a, { col: 0, row: 1 })

const disconnected = layout.normalize(
  perScreen,
  items,
  ["HDMI1"],
  grids
)
equalJson(layout.visibleIds(disconnected, items, ["HDMI1"], "HDMI1").sort(), ["a", "b", "c"])
const reconnected = layout.normalize(disconnected, items, ["HDMI1", "HDMI2"], grids)
assert.strictEqual(layout.homeOf(reconnected, "b"), "HDMI2")

const oneScreen = layout.visibleIds(moved, items, ["HDMI1"], "HDMI1")
equalJson(oneScreen.sort(), ["a", "b", "c"])

const clamped = layout.normalize(
  { version: 3, screens: { HDMI1: { a: { col: 99, row: 99 } } } },
  [{ id: "a" }],
  ["HDMI1"],
  grids
)
equalJson(clamped.screens.HDMI1.a, { col: 7, row: 4 })
equalJson(layout.cellFromPixel(-40, 9000, grid), { col: 0, row: 4 })

const overlapFree = layout.normalize(
  { version: 3, screens: { HDMI1: { a: { col: 0, row: 0 } } } },
  [{ id: "a" }, { id: "b" }],
  ["HDMI1"],
  grids
)
equalJson(overlapFree.screens.HDMI1.a, { col: 0, row: 0 })
assert.notStrictEqual(
  overlapFree.screens.HDMI1.b.col + "," + overlapFree.screens.HDMI1.b.row,
  "0,0"
)

const guests = layout.cellMap(
  { version: 3, screens: { HDMI1: { a: { col: 0, row: 0 } } } },
  ["a", "guest-1", "guest-2"],
  "HDMI1",
  grid
)
equalJson(guests.a, { col: 0, row: 0 })
assert.notStrictEqual(guests["guest-1"].col + "," + guests["guest-1"].row, "0,0")
assert.notStrictEqual(
  guests["guest-1"].col + "," + guests["guest-1"].row,
  guests["guest-2"].col + "," + guests["guest-2"].row
)

const blockedAfterClamp = layout.moveGroup(
  groupState, "HDMI1", "HDMI1",
  [
    { id: "a", targetCell: { col: 0, row: 0 } },
    { id: "b", targetCell: { col: 0, row: 0 } }
  ],
  grid
)
equalJson(blockedAfterClamp, groupState)

console.log("desktop layout model: ok")
