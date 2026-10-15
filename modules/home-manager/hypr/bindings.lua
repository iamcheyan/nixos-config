-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.
--
-- The Hyprland session runs inua as its shell; there is no Omarchy default
-- binding set anymore. The base configuration lives in hypr/base/, and inua
-- declares its own bindings in ~/.config/hypr/inua.lua.

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Toggle dictation with F9. This is the user-level dictation binding.
hl.unbind("F9")
hl.bind("F9", hl.dsp.exec_cmd("voxtype record toggle"), {
  description = "Toggle dictation"
})

-- MINILA-R only: keyd maps a lone Control hold to F24 after 300ms while
-- preserving Ctrl combinations even after that timeout.  F24 is only
-- emitted by the MINILA-R keyd profile, so this binding does not affect
-- other keyboards.  Press starts Voxtype; release transcribes.
-- Ctrl+C/Ctrl+W/etc. remain ordinary Ctrl shortcuts.
hl.unbind("F24")
hl.bind("F24", hl.dsp.exec_cmd("voxtype record start"), {
  description = "MINILA-R Ctrl dictation start"
})
hl.bind("F24", hl.dsp.exec_cmd("voxtype record stop"), {
  release = true,
  description = "MINILA-R Ctrl dictation stop"
})

-- MINILA-R dedicated Muhenkan layer (keyd emits Print / Ctrl+Shift+Print).
-- Muhenkan + S: use Omarchy's native interactive smart-region picker.
-- Shift + Muhenkan + S: save the focused monitor directly, without a picker.
hl.unbind("CTRL + SHIFT + PRINT")
o.bind("CTRL + SHIFT + PRINT", "MINILA-R active monitor screenshot", "nixarchy-screenshot-active-monitor")
o.bind("CTRL + SHIFT + F3", "MINILA-R delayed fullscreen screenshot", "omarchy-delayed-screenshot 3 fullscreen")

-- To use inua's launcher on a different key, unbind and rebind here:
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Launcher", "inua call launcher toggle")

-- Disable a binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Leave Win+C and Win+V available to applications.
hl.unbind("SUPER + C")
hl.unbind("SUPER + V")

-- Hyprland's Lua bind API expects key names here. The Omarchy compatibility
-- defaults use config-file `code:N` spellings, which remain literal keys in
-- Lua mode and do not match the number row.
for workspace = 1, 10 do
  local key = tostring(workspace % 10)
  local code = tostring(workspace + 9)
  pcall(hl.unbind, "SUPER + code:" .. code)
  pcall(hl.unbind, "SUPER + SHIFT + code:" .. code)
  pcall(hl.unbind, "SUPER + SHIFT + ALT + code:" .. code)
  o.bind("SUPER + " .. key, "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
  o.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
  o.bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace), follow = false }))
end

-- Use Alt for mouse window manipulation.
hl.unbind("SUPER + mouse:272")
hl.unbind("SUPER + mouse:273")
o.bind("ALT + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
o.bind("ALT + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

-- Delayed screenshot (script deployed to ~/.local/bin by the Labwc module).
-- Usage: omarchy-delayed-screenshot [seconds] [region|fullscreen]
o.bind("SHIFT + PRINT", "Delayed screenshot", "omarchy-delayed-screenshot 3")

-- Inua owns standalone Win and Win+Tab through its runtime keyboard listener.
-- Keep Alt+Tab's normal window switching bindings.
