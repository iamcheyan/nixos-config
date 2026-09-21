-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- Remove all spacing between tiled windows and between windows and the monitor
-- edges. Borders remain visible when multiple windows are open.
hl.config({
  general = {
    gaps_in = 0,
    gaps_out = 0,
    -- Allow the mouse to resize tiled windows by dragging their shared edge.
    resize_on_border = true,
    -- Make the border easier to grab on a HiDPI display.
    extend_border_grab_area = 12,
    hover_icon_on_border = true,
  },
})

-- Practical mode: override Omarchy's default per-window opacity rule and keep
-- every normal application fully opaque, including unfocused tiled windows.
o.window(".*", { opacity = "1 1" })

hl.config({
  decoration = {
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    fullscreen_opacity = 1.0,
    dim_inactive = false,
    shadow = { enabled = false },
    blur = { enabled = false },
  },
  animations = {
    enabled = false,
  },
})

-- A lone tiled window still uses the normal border, keeping the appearance
-- consistent with multi-window workspaces.
hl.workspace_rule({
  workspace = "w[tv1]s[false]",
  gaps_out = 0,
  gaps_in = 0,
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })
