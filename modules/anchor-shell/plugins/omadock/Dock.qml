import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "DockModel.js" as DockModel

Item {
  id: root
  property var shell: null
  property var manifest: null

  property var pinnedApps: []
  property var dockSettings: ({
    iconSize: 22, iconBox: 28, iconGap: 2, dockWidth: 40,
    pillPad: 6, pillRadius: 16, opacity: 86, itemRadius: 8
  })
  property int cacheGeneration: 0
  property var entryCache: ({})
  property var iconCache: ({})
  property var nameCache: ({})

  FileView {
    id: dockConfigFile
    path: (Quickshell.env("ANCHOR_SHELL_CONFIG_DIR") || (Quickshell.env("HOME") + "/.config/anchor-shell")) + "/dock.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadConfig()
    onFileChanged: reload()
  }

  function loadConfig() {
    var text = (dockConfigFile.text() || "").trim()
    if (text) {
      try {
        var data = JSON.parse(text)
        root.pinnedApps = Array.isArray(data.pinned)
          ? data.pinned : ["org.kde.dolphin", "kitty", "firefox", "codex-desktop"]
        var defaults = { iconSize: 22, iconBox: 28, iconGap: 2, dockWidth: 40,
          pillPad: 6, pillRadius: 16, opacity: 86, itemRadius: 8 }
        var limits = { iconSize: [14, 36], iconBox: [24, 52], iconGap: [0, 18],
          dockWidth: [36, 76], pillPad: [2, 20], pillRadius: [8, 32],
          opacity: [20, 100], itemRadius: [0, 20] }
        var settings = data.settings || {}
        for (var key in defaults) {
          var value = Number(settings[key])
          if (isFinite(value)) defaults[key] = Math.max(limits[key][0], Math.min(limits[key][1], value))
        }
        if (defaults.iconBox < defaults.iconSize + 4)
          defaults.iconSize = Math.max(14, defaults.iconBox - 4)
        root.dockSettings = defaults
        return
      } catch (e) {
        console.warn("dock.json parse failed:", e)
      }
    }
    root.pinnedApps = ["org.kde.dolphin", "kitty", "firefox", "codex-desktop"]
  }

  function saveConfig() {
    dockConfigFile.setText(JSON.stringify({ pinned: root.pinnedApps, settings: root.dockSettings }, null, 2) + "\n")
  }

  function setDockSetting(name, value) {
    var limits = { iconSize: [14, 36], iconBox: [24, 52], iconGap: [0, 18],
      dockWidth: [36, 76], pillPad: [2, 20], pillRadius: [8, 32],
      opacity: [20, 100], itemRadius: [0, 20] }
    if (!limits[name]) return
    var next = Object.assign({}, root.dockSettings)
    next[name] = Math.max(limits[name][0], Math.min(limits[name][1], Math.round(value)))
    // Keep icon boxes comfortably larger than their image.
    if (name === "iconSize" && next.iconBox < next.iconSize + 4) next.iconBox = Math.min(52, next.iconSize + 4)
    if (name === "iconBox" && next.iconBox < next.iconSize + 4) next.iconSize = Math.max(14, next.iconBox - 4)
    root.dockSettings = next
    settingsSaveTimer.restart()
  }

  function saveLinkedBarOpacity() {
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return
    var opacity = root.dockSettings.opacity / 100
    var currentBar = root.shell.barConfig || ({})
    if (typeof currentBar.backgroundOpacity === "number"
        && Math.abs(currentBar.backgroundOpacity - opacity) < 0.005
        && currentBar.transparent !== true) return
    root.shell.mutateShellConfig(function(config) {
      if (!config.bar || typeof config.bar !== "object") config.bar = {}
      config.bar.backgroundOpacity = opacity
      // The linked slider controls translucency; disable the separate
      // fully-transparent mode so the top bar follows the same percentage.
      config.bar.transparent = false
    })
  }

  function resetDockSettings() {
    root.dockSettings = { iconSize: 22, iconBox: 28, iconGap: 2, dockWidth: 40,
      pillPad: 6, pillRadius: 16, opacity: 86, itemRadius: 8 }
    settingsSaveTimer.restart()
  }

  Timer {
    id: settingsSaveTimer
    interval: 180
    repeat: false
    onTriggered: {
      root.saveConfig()
      root.saveLinkedBarOpacity()
    }
  }

  function invalidateLookups() {
    root.entryCache = ({})
    root.iconCache = ({})
    root.nameCache = ({})
    root.cacheGeneration++
  }

  function isPinned(appId) {
    return root.pinnedApps.indexOf(DockModel.stripDesktop(appId)) !== -1
  }

  function pinApp(appId) {
    var clean = DockModel.stripDesktop(appId)
    if (!clean || root.pinnedApps.indexOf(clean) !== -1) return
    var next = root.pinnedApps.slice()
    next.push(clean)
    root.pinnedApps = next
    saveConfig()
  }

  function unpinApp(appId) {
    var clean = DockModel.stripDesktop(appId)
    root.pinnedApps = root.pinnedApps.filter(function(id) { return id !== clean })
    saveConfig()
  }

  function commitOrder(visualIds, draggedId) {
    var next = DockModel.pinnedFromVisual(visualIds, draggedId, root.pinnedApps)
    if (DockModel.sameIdList(next, root.pinnedApps)) return
    root.pinnedApps = next
    saveConfig()
  }

  function entryFor(appId) {
    if (!appId) return null
    var clean = DockModel.stripDesktop(appId)
    if (Object.prototype.hasOwnProperty.call(root.entryCache, clean))
      return root.entryCache[clean]

    var entry = DesktopEntries.heuristicLookup(clean) || DesktopEntries.byId(clean) || DesktopEntries.byId(appId)
    if (!entry) {
      var entries = DesktopEntries.applications.values || []
      var lower = clean.toLowerCase()
      for (var i = 0; i < entries.length; i++) {
        var eid = DockModel.stripDesktop(entries[i].id).toLowerCase()
        if (eid === lower) { entry = entries[i]; break }
      }
      if (!entry) {
        for (var j = 0; j < entries.length; j++) {
          if (String(entries[j].name || "").toLowerCase() === lower) {
            entry = entries[j]
            break
          }
        }
      }
    }
    root.entryCache[clean] = entry || null
    return entry || null
  }

  function iconFor(appId) {
    var clean = DockModel.stripDesktop(appId)
    if (Object.prototype.hasOwnProperty.call(root.iconCache, clean))
      return root.iconCache[clean]

    var entry = entryFor(appId)
    var value = ""
    if (entry && entry.icon) {
      if (shell && shell.appLibrary) value = shell.appLibrary.iconSource(entry.icon)
      else value = Quickshell.iconPath(entry.icon, true)
    }
    if (!value) {
      value = Quickshell.iconPath(clean, true) || Quickshell.iconPath(clean.toLowerCase(), true)
    }
    if (!value) value = Quickshell.iconPath("application-x-executable", true)
    root.iconCache[clean] = value
    return value
  }

  function nameFor(appId) {
    var clean = DockModel.stripDesktop(appId)
    if (Object.prototype.hasOwnProperty.call(root.nameCache, clean))
      return root.nameCache[clean]

    var entry = entryFor(appId)
    var value = ""
    if (entry && entry.name) {
      value = entry.name
    } else {
      var lastDot = clean.lastIndexOf(".")
      if (lastDot >= 0 && lastDot < clean.length - 1) clean = clean.slice(lastDot + 1)
      value = clean ? (clean.charAt(0).toUpperCase() + clean.slice(1)) : ""
    }
    root.nameCache[DockModel.stripDesktop(appId)] = value
    return value
  }

  function launchApp(appId) {
    var clean = DockModel.stripDesktop(appId)
    var entry = entryFor(clean)
    if (entry && shell && shell.appLibrary) {
      shell.appLibrary.launch(entry.id, entry.name || clean)
    } else if (entry) {
      Util.execGraphical(["gtk-launch", entry.id])
    } else {
      Util.execGraphical(["gtk-launch", clean + ".desktop"])
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.invalidateLookups() }
  }

  Connections {
    target: root.shell && root.shell.appLibrary ? root.shell.appLibrary : null
    function onAppsChanged() { root.invalidateLookups() }
  }

  Variants {
    model: Quickshell.screens
    delegate: DockSurface {
      required property var modelData
      screen: modelData
      shell: root.shell
      dockRoot: root
    }
  }
}
