const assert = require("assert")
const fs = require("fs")
const vm = require("vm")

const sourcePath = `${__dirname}/../DesktopLayout.js`
const source = fs.readFileSync(sourcePath, "utf8")
  .replace(/^\.pragma library\s*/, "")
  + `\nthis.layout = {\n`
  + [
    "empty", "cellFromPixel", "pixelFromCell", "homeOf", "normalize",
    "repair", "visibleIds", "position", "moveOrSwap", "moveToScreen"
  ].map(name => `${name},`).join("\n")
  + "}\n"

const context = { Math, JSON, String, Number, Object, Array }
vm.createContext(context)
vm.runInContext(source, context, { filename: sourcePath })
const layout = context.layout
const grid = { left: 24, top: 48, cellW: 96, cellH: 104, rows: 5 }
const items = [{ id: "a" }, { id: "b" }, { id: "c" }]
const equalJson = (actual, expected) =>
  assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected))

let state = layout.normalize(
  { version: 3, screens: { HDMI1: { a: { col: 0, row: 0 }, b: { col: 0, row: 0 } } } },
  items,
  ["HDMI1", "HDMI2"],
  grid
)
assert.notStrictEqual(state.screens.HDMI1.a.col + "," + state.screens.HDMI1.a.row,
  state.screens.HDMI1.b.col + "," + state.screens.HDMI1.b.row)
assert.strictEqual(layout.homeOf(state, "c"), "HDMI1")

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

equalJson(layout.cellFromPixel(120, 160, grid), { col: 1, row: 1 })
equalJson(layout.pixelFromCell({ col: 1, row: 1 }, grid), { x: 120, y: 152 })

const oneScreen = layout.visibleIds(moved, items, ["HDMI1"], "HDMI1")
equalJson(oneScreen.sort(), ["a", "b", "c"])

console.log("desktop layout model: ok")
