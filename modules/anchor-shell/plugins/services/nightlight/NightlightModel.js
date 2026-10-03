// Temperatures below the identity point count as night light. Keep in sync
// with bin/omarchy-display-nightlight and the panel's Model.js, which use the
// same threshold.
var IDENTITY_TEMPERATURE = 6000
var DAY_TEMPERATURE = 6500
var MIN_TEMPERATURE = 2500
var MAX_TEMPERATURE = 6500

function isNightlight(temperature) {
  var n = Number(temperature)
  return isFinite(n) && n < IDENTITY_TEMPERATURE
}

function clampTemperature(value) {
  var n = Number(value)
  if (!isFinite(n)) return DAY_TEMPERATURE
  var stepped = Math.round(n / 250) * 250
  return Math.max(MIN_TEMPERATURE, Math.min(MAX_TEMPERATURE, stepped))
}

// Pull the temperature out of `omarchy-display-nightlight`'s status JSON.
// Returns null when the payload is unusable so callers keep their current
// value instead of snapping to a default.
function parseStatus(output) {
  var payload = null
  try {
    payload = JSON.parse(String(output || ""))
  } catch (error) {
    payload = null
  }
  if (!payload || typeof payload !== "object") return null
  // Number(null) and Number("") are both 0, which would clamp to the warmest
  // stop and silently turn night light on; require a real numeric field.
  var raw = payload.temperature
  if (raw === null || raw === undefined || raw === "") return null
  var value = Number(raw)
  return isFinite(value) ? clampTemperature(value) : null
}

if (typeof module !== "undefined") {
  module.exports = {
    IDENTITY_TEMPERATURE: IDENTITY_TEMPERATURE,
    DAY_TEMPERATURE: DAY_TEMPERATURE,
    MIN_TEMPERATURE: MIN_TEMPERATURE,
    MAX_TEMPERATURE: MAX_TEMPERATURE,
    isNightlight: isNightlight,
    clampTemperature: clampTemperature,
    parseStatus: parseStatus
  }
}
