-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Toggle dictation with F9. This overrides Omarchy's default push-to-talk
-- binding while keeping the command in the user configuration layer.
hl.unbind("F9")
hl.bind("F9", hl.dsp.exec_cmd("voxtype record toggle"), {
  description = "Toggle dictation"
})

-- MINILA-R only: keyd maps a standalone left Ctrl release to F24 while
-- preserving Ctrl combinations through overload(control, f24).  F24 is only
-- emitted by the MINILA-R keyd profile, so this binding does not affect other
-- keyboards.  A press-release toggles Voxtype; Ctrl+C/Ctrl+W/etc. remain
-- ordinary Ctrl shortcuts.
hl.unbind("F24")
hl.bind("F24", hl.dsp.exec_cmd("voxtype record toggle"), {
  release = true,
  description = "MINILA-R Ctrl dictation"
})

-- MINILA-R dedicated Muhenkan layer (keyd emits Print / Ctrl+Shift+Print).
-- Muhenkan + S: use Omarchy's native interactive smart-region picker.
-- Shift + Muhenkan + S: save the focused monitor directly, without a picker.
hl.unbind("CTRL + SHIFT + PRINT")
o.bind("CTRL + SHIFT + PRINT", "MINILA-R active monitor screenshot", "nixarchy-screenshot-active-monitor")
o.bind("CTRL + SHIFT + F3", "MINILA-R delayed fullscreen screenshot", "omarchy-delayed-screenshot 3 fullscreen")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Delayed screenshot (script managed by chezmoi at ~/.local/bin/).
-- Usage: omarchy-delayed-screenshot [seconds] [region|fullscreen]
o.bind("SHIFT + PRINT", "Delayed screenshot", "omarchy-delayed-screenshot 3")
