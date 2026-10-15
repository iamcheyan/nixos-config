-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Module path for this configuration. Omarchy's own bootstrap is not used:
-- the Hyprland session runs inua as its shell and carries its base
-- configuration in hypr/base/ rather than loading $OMARCHY_PATH.
-- dofile with an absolute path, so this works before package.path is extended.
dofile((os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")) .. "/hypr/bootstrap.lua")

-- Base configuration carried over from Omarchy's defaults, so the session
-- keeps its Wayland environment, input settings and window rules.
require("hypr.base.helpers")
require("hypr.base.envs")
require("hypr.base.input")
require("hypr.base.windows")
require("hypr.base.looknfeel")

-- Personal overrides, loaded after the base so they win.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Inua shell integration (keybindings and settings). Keep this last.
pcall(require, "inua")
