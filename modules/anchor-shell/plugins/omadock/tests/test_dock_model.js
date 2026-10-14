const assert = require("assert")
const fs = require("fs")
const vm = require("vm")

const sourcePath = `${__dirname}/../DockModel.js`
const source = fs.readFileSync(sourcePath, "utf8")
  .replace(/^\.pragma library\s*/, "")
  + `\nthis.model = {\n`
  + [
    "stripDesktop", "iconIsRaster", "windowOnScreen", "windowListMatch",
    "fieldsMatch", "listsMatch", "containsApp", "buildApps",
    "moveItem", "sameIdList", "uniqueIds", "pinnedFromVisual"
  ].map(name => `${name},`).join("\n")
  + "}\n"

const context = { Math, JSON, String, Number, Object, Array }
vm.createContext(context)
vm.runInContext(source, context, { filename: sourcePath })
const model = context.model

assert.strictEqual(model.stripDesktop("firefox.desktop"), "firefox")
assert.strictEqual(model.stripDesktop("org.kde.dolphin"), "org.kde.dolphin")
assert.strictEqual(model.iconIsRaster("file:///usr/share/icons/app.svg"), false)
assert.strictEqual(model.iconIsRaster("file:///usr/share/icons/app.png"), true)

const hdmi1 = { name: "HDMI-A-1" }
const hdmi2 = { name: "HDMI-A-2" }
const firefox = { appId: "firefox.desktop", screens: [hdmi1], activated: true }
const kitty = { appId: "kitty", screens: [hdmi1], activated: false }
const chrome = { appId: "google-chrome", screens: [hdmi2], activated: true }
const orphan = { appId: "foot", screens: [], activated: false }

assert.strictEqual(model.windowOnScreen(firefox, hdmi1, null), true)
assert.strictEqual(model.windowOnScreen(firefox, hdmi2, null), false)
assert.strictEqual(model.windowOnScreen(orphan, hdmi1, orphan), true)
assert.strictEqual(model.windowOnScreen(orphan, hdmi1, firefox), false)

const apps = model.buildApps({
  pinnedApps: ["firefox", "kitty", "codex-desktop"],
  toplevels: [firefox, kitty, chrome],
  screen: hdmi1,
  activeToplevel: firefox,
  nameFor: function(id) { return id },
  iconFor: function(id) { return "icon:" + id }
})

assert.strictEqual(apps.length, 3)
assert.strictEqual(apps[0].id, "firefox")
assert.strictEqual(apps[0].isPinned, true)
assert.strictEqual(apps[0].isRunning, true)
assert.strictEqual(apps[0].isActive, true)
assert.strictEqual(apps[1].id, "kitty")
assert.strictEqual(apps[1].isRunning, true)
assert.strictEqual(apps[1].isActive, false)
assert.strictEqual(apps[2].id, "codex-desktop")
assert.strictEqual(apps[2].isRunning, false)
assert.strictEqual(apps.some(function(a) { return a.id === "google-chrome" }), false)

const withChrome = model.buildApps({
  pinnedApps: ["firefox"],
  toplevels: [firefox, chrome],
  screen: hdmi2,
  activeToplevel: chrome,
  nameFor: function(id) { return id },
  iconFor: function() { return "" }
})
assert.strictEqual(withChrome.length, 2)
assert.strictEqual(withChrome[0].id, "firefox")
assert.strictEqual(withChrome[0].isRunning, false)
assert.strictEqual(withChrome[0].windows.length, 0)
assert.strictEqual(withChrome[1].id, "google-chrome")
assert.strictEqual(withChrome[1].isPinned, false)
assert.strictEqual(withChrome[1].isSeparatorBefore, true)

const again = model.buildApps({
  pinnedApps: ["firefox"],
  toplevels: [firefox, chrome],
  screen: hdmi2,
  activeToplevel: chrome,
  nameFor: function(id) { return id },
  iconFor: function() { return "" }
})
assert.strictEqual(model.listsMatch(withChrome, again), true)

const focused = model.buildApps({
  pinnedApps: ["firefox"],
  toplevels: [{ appId: "firefox", screens: [hdmi2], activated: true }, chrome],
  screen: hdmi2,
  activeToplevel: firefox,
  nameFor: function(id) { return id },
  iconFor: function() { return "" }
})
assert.strictEqual(model.listsMatch(withChrome, focused), false)
assert.strictEqual(model.containsApp(focused, "firefox"), true)
assert.strictEqual(model.containsApp(focused, "missing"), false)

const equalJson = function(actual, expected) {
  assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected))
}

equalJson(model.moveItem(["a", "b", "c", "d"], 1, 3), ["a", "c", "d", "b"])
equalJson(model.moveItem(["a", "b", "c"], 2, 0), ["c", "a", "b"])
equalJson(model.moveItem(["a", "b"], 0, 0), ["a", "b"])
equalJson(model.moveItem(["a", "b"], -1, 0), ["a", "b"])
assert.strictEqual(model.sameIdList(["firefox.desktop", "kitty"], ["firefox", "kitty"]), true)
assert.strictEqual(model.sameIdList(["firefox", "kitty"], ["kitty", "firefox"]), false)

equalJson(
  model.pinnedFromVisual(["term", "firefox", "chrome"], "firefox", []),
  ["term", "firefox", "chrome"]
)
equalJson(
  model.pinnedFromVisual(["chrome", "firefox", "kitty", "term"], "chrome", ["firefox", "kitty", "chrome"]),
  ["chrome", "firefox", "kitty"]
)
equalJson(
  model.pinnedFromVisual(["firefox", "term", "kitty", "chrome"], "term", ["firefox", "kitty", "chrome"]),
  ["firefox", "term", "kitty", "chrome"]
)
equalJson(
  model.pinnedFromVisual(["firefox", "kitty", "term", "chrome"], "chrome", ["firefox", "kitty", "chrome"]),
  ["firefox", "kitty", "term", "chrome"]
)

console.log("ok")
