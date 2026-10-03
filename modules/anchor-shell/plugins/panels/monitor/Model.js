// Pure helpers for the Display panel. Kept free of QML imports so the same
// file can be exercised by node (see tests/test_display_model.js).

function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

// Hyprland only accepts scales where the mode divides into whole logical
// pixels (in 1/120 steps). wlroots takes any factor, so this is applied on the
// Hyprland path only.
function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

// Playful mood-name for a given brightness percent. Bands intentionally span
// ~10-20 points so casual tweaks change the label, while small nudges within
// one band don't.
function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

// --------------------------------------------------------------- geometry

function resolutionKey(mode) {
  if (!mode) return ""
  return String(mode.width) + "x" + String(mode.height)
}

function resolutionLabel(mode) {
  if (!mode) return ""
  return String(mode.width) + "x" + String(mode.height)
}

function modeKey(mode) {
  if (!mode) return ""
  return resolutionKey(mode) + "@" + formatRefresh(mode.refresh)
}

function formatRefresh(refresh) {
  var n = Number(refresh)
  if (!isFinite(n) || n <= 0) return ""
  // 59.939999 -> 59.94, 60.000000 -> 60
  var rounded = Math.round(n * 100) / 100
  return String(rounded)
}

function modeLabel(mode) {
  if (!mode) return ""
  var refresh = formatRefresh(mode.refresh)
  return resolutionLabel(mode) + (refresh === "" ? "" : " @ " + refresh + "Hz")
}

// The display helper accepts WxH@RHz and passes it to wlr-randr verbatim.
function modeArgument(mode) {
  if (!mode) return ""
  var refresh = formatRefresh(mode.refresh)
  return resolutionKey(mode) + (refresh === "" ? "" : "@" + refresh + "Hz")
}

// Distinct resolutions in the mode list, largest first, keeping a flag for the
// one currently driving the output. Defaults come from the panel's curated
// list; this preserves whatever the monitor actually advertises.
function distinctResolutions(modes) {
  if (!Array.isArray(modes)) return []
  var seen = {}
  var out = []
  for (var i = 0; i < modes.length; i++) {
    var mode = modes[i]
    if (!mode || !(mode.width > 0) || !(mode.height > 0)) continue
    var key = resolutionKey(mode)
    var entry = seen[key]
    if (!entry) {
      entry = {
        key: key,
        label: resolutionLabel(mode),
        width: mode.width,
        height: mode.height,
        preferred: mode.preferred === true,
        current: false
      }
      seen[key] = entry
      out.push(entry)
    }
    if (mode.preferred === true) entry.preferred = true
    if (mode.current === true) entry.current = true
  }
  out.sort(function(a, b) {
    if (a.preferred !== b.preferred) return a.preferred ? -1 : 1
    return (b.width * b.height) - (a.width * a.height)
  })
  return out
}

// Refresh choices available at one resolution, fastest first.
function refreshesFor(modes, resolution) {
  if (!Array.isArray(modes) || !resolution) return []
  var seen = {}
  var out = []
  for (var i = 0; i < modes.length; i++) {
    var mode = modes[i]
    if (!mode || resolutionKey(mode) !== resolution) continue
    var key = formatRefresh(mode.refresh)
    if (key === "" || seen[key]) continue
    seen[key] = true
    out.push({
      key: key,
      label: key + " Hz",
      refresh: Number(mode.refresh),
      mode: mode,
      preferred: mode.preferred === true
    })
  }
  out.sort(function(a, b) { return b.refresh - a.refresh })
  return out
}

// The mode entry the compositor reports as driving the output.
function currentMode(display) {
  if (!display || !Array.isArray(display.modes)) return null
  for (var i = 0; i < display.modes.length; i++) {
    if (display.modes[i] && display.modes[i].current === true) return display.modes[i]
  }
  return null
}

function refreshIndex(refreshes, currentRefresh) {
  var current = Number(currentRefresh)
  if (!Array.isArray(refreshes) || !isFinite(current)) return -1
  for (var i = 0; i < refreshes.length; i++) {
    if (formatRefresh(refreshes[i].refresh) === formatRefresh(current)) return i
  }
  return -1
}

// "3840x2160 @ 59.94Hz - 2x" style one-liner for the hero.
function displaySummary(display) {
  if (!display) return ""
  if (display.enabled === false) return "Disabled"
  var parts = []
  var mode = currentMode(display)
  if (mode) parts.push(modeLabel(mode))
  var scale = normalizeScale(display.scale)
  if (scale !== "") parts.push(scale + "x")
  var transform = String(display.transform || "normal")
  if (transform !== "normal") parts.push(transform + "deg")
  return parts.join(" - ")
}

function scalePillLabel(scale) {
  return normalizeScale(scale) + "x"
}

// --------------------------------------------------------------- transforms

var TRANSFORMS = ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]

// Rotation presets offered in the UI: the four upright orientations.
var ROTATIONS = ["normal", "90", "180", "270"]

function rotationLabel(transform) {
  var value = String(transform || "normal")
  if (value === "normal" || value === "0") return "0deg"
  if (value === "90" || value === "180" || value === "270") return value + "deg"
  if (value.indexOf("flipped") === 0) {
    var suffix = value.slice("flipped".length).replace("-", "")
    return suffix === "" ? "Flipped" : "Flipped " + suffix + "deg"
  }
  return value
}

function rotationIndex(transform) {
  var value = String(transform || "normal")
  if (value === "0") value = "normal"
  var index = ROTATIONS.indexOf(value)
  return index
}

function isTransform(value) {
  return TRANSFORMS.indexOf(String(value)) >= 0
}

// --------------------------------------------------------------- parsing

// The helper emits {"session":..,"focused":..,"displays":[..]}. Tolerate a
// bare array and a missing payload so a failed probe degrades to "no data"
// instead of throwing inside a binding.
function parseState(raw) {
  var payload = null
  try {
    payload = raw ? JSON.parse(String(raw)) : null
  } catch (error) {
    payload = null
  }

  var displays = []
  var focused = ""
  var session = "labwc"

  if (Array.isArray(payload)) {
    displays = payload
  } else if (payload && typeof payload === "object") {
    if (Array.isArray(payload.displays)) displays = payload.displays
    if (typeof payload.focused === "string") focused = payload.focused
    if (typeof payload.session === "string") session = payload.session
  }

  var clean = []
  var enabledCount = 0
  for (var i = 0; i < displays.length; i++) {
    var display = displays[i]
    if (!display || typeof display !== "object" || !display.name) continue
    if (display.enabled !== false) enabledCount++
    clean.push(display)
  }

  var target = null
  for (var j = 0; j < clean.length; j++) {
    if (clean[j].name === focused) { target = clean[j]; break }
  }
  if (!target) {
    for (var k = 0; k < clean.length; k++) {
      if (clean[k].enabled !== false) { target = clean[k]; break }
    }
  }
  if (!target && clean.length > 0) target = clean[0]

  return {
    session: session,
    focused: target ? target.name : "",
    displays: clean,
    target: target,
    enabledDisplayCount: enabledCount
  }
}

function findDisplay(displays, name) {
  if (!Array.isArray(displays)) return null
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].name === name) return displays[i]
  }
  return null
}

// --------------------------------------------------------------- night mode

var DEFAULT_NIGHT_TEMPERATURE = 4000
var DEFAULT_DAY_TEMPERATURE = 6500
var TEMPERATURE_MIN = 2500
var TEMPERATURE_MAX = 6500
var TEMPERATURE_STEP = 250

function clampTemperature(value) {
  var n = Number(value)
  if (!isFinite(n)) return DEFAULT_NIGHT_TEMPERATURE
  var stepped = Math.round(n / TEMPERATURE_STEP) * TEMPERATURE_STEP
  return Math.max(TEMPERATURE_MIN, Math.min(TEMPERATURE_MAX, stepped))
}

// Descending so a slider runs day (left) to night (right): further right means
// warmer and dimmer. The numeric readout stays authoritative, so the direction
// is only a convenience.
function temperatureStops() {
  var stops = []
  for (var t = TEMPERATURE_MAX; t >= TEMPERATURE_MIN; t -= TEMPERATURE_STEP) stops.push(t)
  return stops
}

function temperatureLabel(value) {
  return clampTemperature(value) + "K"
}

// Below this a temperature is warm enough to call it night mode; matches the
// threshold in bin/omarchy-toggle-nightlight and NightlightModel.js.
var IDENTITY_TEMPERATURE = 6000

function isNightTemperature(temperature) {
  var n = Number(temperature)
  return isFinite(n) && n < IDENTITY_TEMPERATURE
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    availableScales: availableScales,
    matchingScaleIndex: matchingScaleIndex,
    brightnessName: brightnessName,
    resolutionKey: resolutionKey,
    resolutionLabel: resolutionLabel,
    modeKey: modeKey,
    modeLabel: modeLabel,
    modeArgument: modeArgument,
    formatRefresh: formatRefresh,
    distinctResolutions: distinctResolutions,
    refreshesFor: refreshesFor,
    currentMode: currentMode,
    refreshIndex: refreshIndex,
    displaySummary: displaySummary,
    scalePillLabel: scalePillLabel,
    TRANSFORMS: TRANSFORMS,
    ROTATIONS: ROTATIONS,
    rotationLabel: rotationLabel,
    rotationIndex: rotationIndex,
    isTransform: isTransform,
    parseState: parseState,
    findDisplay: findDisplay,
    DEFAULT_NIGHT_TEMPERATURE: DEFAULT_NIGHT_TEMPERATURE,
    DEFAULT_DAY_TEMPERATURE: DEFAULT_DAY_TEMPERATURE,
    TEMPERATURE_MIN: TEMPERATURE_MIN,
    TEMPERATURE_MAX: TEMPERATURE_MAX,
    TEMPERATURE_STEP: TEMPERATURE_STEP,
    clampTemperature: clampTemperature,
    temperatureStops: temperatureStops,
    temperatureLabel: temperatureLabel,
    IDENTITY_TEMPERATURE: IDENTITY_TEMPERATURE,
    isNightTemperature: isNightTemperature
  }
}
