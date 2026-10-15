-- Base window rules for the Hyprland session.
--
-- Carried here from Omarchy's default.hypr.windows and default.hypr.apps now
-- that the Hyprland session no longer loads Omarchy's modules. The
-- Omarchy-Quickshell surface rules (omarchy-bar, the shell's own dialogs) are
-- gone with the shell; inua declares its own layer and window rules in
-- ~/.config/hypr/inua.lua.
--
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/

o.window(".*", { suppress_event = "maximize" })

-- Tag all windows for default opacity (apps can override with -default-opacity).
o.window(".*", { tag = "+default-opacity" })

-- Fix some dragging issues with XWayland.
o.window(
  {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  { no_focus = true }
)

-- Apply default opacity after the app rules below have had a chance to opt out.
o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })

--------------------------------------------------------------------------------
-- Per-application tweaks (from Omarchy's default.hypr.apps).
--------------------------------------------------------------------------------

-- Floating windows.
o.window({ tag = "floating-window" }, { float = true })
o.window({ tag = "floating-window" }, { center = true })
o.window({ tag = "floating-window" }, { size = { 875, 600 } })

o.window(
  "(org.omarchy.btop|org.omarchy.terminal|org.omarchy.bash|org.codeberg.dnkl.foot|org.gnome.NautilusPreviewer|org.gnome.Evince|Omarchy|About|TUI.float|imv|mpv)",
  {
    tag = "+floating-window",
  }
)

-- The portal only shows dialogs — file pickers, screen shares, permission
-- prompts — so every window it opens belongs in the floating treatment.
o.window("xdg-desktop-portal-gtk", { tag = "+floating-window" })
o.window({
  class = "(sublime_text|DesktopEditors|org.gnome.Nautilus)",
  title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
}, { tag = "+floating-window" })

o.window("dev.tensaku.Tensaku", { float = true })
o.window("dev.tensaku.Tensaku", { center = true })
o.window("omacalc", { float = true })

-- No transparency on media windows.
o.window(
  "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
  {
    tag = "-default-opacity",
  }
)
o.window(
  "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
  {
    opacity = "1 1",
  }
)

-- Popped window rounding.
o.window({ tag = "pop" }, { rounding = 8 })

-- Prevent idle while open.
o.window({ tag = "noidle" }, { idle_inhibit = "always" })

-- Terminals and browsers: keep them tiled and readable.
o.window("(Alacritty|kitty|foot|com.mitchellh.ghostty)", { tag = "+terminal" })
o.window("(firefox|chromium|google-chrome|microsoft-edge)", { tag = "+browser" })
