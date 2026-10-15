-- Hyprland Lua module path for this configuration.
--
-- This replaces Omarchy's default.hypr bootstrap, which pointed module
-- resolution at $OMARCHY_PATH. The Hyprland session no longer loads Omarchy's
-- configuration layer, so only the user's own files are on the search path:
--   require("hypr.monitors")    -> ~/.config/hypr/monitors.lua
--   require("hypr.base.helpers")-> ~/.config/hypr/base/helpers.lua
--   require("base.helpers")     -> ~/.config/base/helpers.lua (unused)

local home = os.getenv("HOME")

-- Drop our modules from the cache on reload so an edited file is re-read
-- instead of the stale copy Hyprland loaded the first time.
local reload_prefixes = {
  "hypr",
}

local function should_reload_module(module)
  for _, prefix in ipairs(reload_prefixes) do
    if module == prefix or module:sub(1, #prefix + 1) == prefix .. "." then
      return true
    end
  end

  return false
end

local modules_to_reload = {}
for module in pairs(package.loaded) do
  if should_reload_module(module) then
    table.insert(modules_to_reload, module)
  end
end

for _, module in ipairs(modules_to_reload) do
  package.loaded[module] = nil
end

package.path = home .. "/.config/?.lua;" .. package.path
