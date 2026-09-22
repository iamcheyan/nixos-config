.pragma library

function stripJsonc(raw) {
  return String(raw || "")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "")
    .replace(/,\s*([}\]])/g, "$1")
}

function parse(raw) {
  try {
    var value = JSON.parse(stripJsonc(raw))
    return value && typeof value === "object" ? value : ({})
  } catch (error) {
    console.warn("iamcheyan.launcher: failed to parse menu JSONC", error)
    return ({})
  }
}

function merge(defaults, overrides) {
  var result = ({})
  var key
  defaults = defaults || ({})
  overrides = overrides || ({})
  for (key in defaults) result[key] = defaults[key]
  for (key in overrides) {
    if (result[key] && typeof result[key] === "object" && typeof overrides[key] === "object") {
      var merged = ({})
      for (var nested in result[key]) merged[nested] = result[key][nested]
      for (nested in overrides[key]) merged[nested] = overrides[key][nested]
      result[key] = merged
    } else {
      result[key] = overrides[key]
    }
  }
  return result
}

function parentId(id) {
  var dot = id.lastIndexOf(".")
  return dot < 0 ? "root" : id.slice(0, dot)
}

function isParent(id, items) {
  var prefix = id + "."
  for (var key in items) {
    if (key.indexOf(prefix) === 0) return true
  }
  return false
}

function pathLabel(id, items) {
  var parts = []
  var current = id
  while (current && current !== "root") {
    var item = items[current]
    if (item && item.label) parts.unshift(String(item.label))
    current = item ? parentId(current) : "root"
  }
  return parts.slice(0, -1).join(" / ")
}

function flatten(defaults, overrides) {
  var items = merge(defaults, overrides)
  var rows = []
  var keys = Object.keys(items)

  for (var i = 0; i < keys.length; i++) {
    var id = keys[i]
    var item = items[id] || ({})
    var hasAction = typeof item.action === "string" && item.action.length > 0
    var isProvider = item.provider === "apps"
    if (!hasAction && !isProvider) continue

    rows.push({
      id: id,
      kind: isProvider ? "apps" : "action",
      label: String(item.label || id),
      icon: String(item.icon || ""),
      description: String(item.description || ""),
      action: hasAction ? String(item.action) : "",
      path: pathLabel(id, items),
      when: String(item.when || ""),
      checked: String(item.checked || "")
    })
  }

  rows.sort(function(a, b) {
    var ap = a.path.toLowerCase()
    var bp = b.path.toLowerCase()
    return ap.localeCompare(bp) || a.label.toLowerCase().localeCompare(b.label.toLowerCase())
  })
  return rows
}
