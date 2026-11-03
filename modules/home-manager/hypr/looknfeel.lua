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
    -- Blur is on for the shell's glass: the bar, the dock, the launcher and
    -- the widget page are half-transparent by inua's style.transparency and
    -- read as frosted glass only over a blur. Windows stay opaque above
    -- (the opacity rule), so nothing else of the desktop is blurred.
    blur = { enabled = true, size = 8, passes = 2 },
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

-- The shell's translucent surfaces need their own layer rule for blur.
-- This matches the upstream Hyprland sample, including the dock drawer.
hl.layer_rule({
  name = "inua-blur",
  match = { namespace = "^inua-(bar|launcher|control|calendar|passwords|center|banners|dock|drawer|osd|widgets)$" },
  blur = true,
  ignore_alpha = 0.6,
})

hl.layer_rule({
  name = "inua-no-anim",
  match = { namespace = "^inua-(launcher|control|calendar|center|banners|dock|drawer|osd|widgets)$" },
  no_anim = true,
})

-- The shell's surfaces are translucent; blur what is behind them. These are
-- the layer-shell namespaces it uses (inua-center is the notification
-- center, inua-banners its banners, inua-calendar the calendar panel under
-- the clock, inua-dock the app dock, inua-drawer the dock's drawer, inua-osd
-- the volume and brightness indicator, inua-widgets the widget page).
--
-- A layer surface takes its blur from its own rule, never from
-- decoration.blur.enabled: without this the shell's glass (inua's
-- style.transparency) sits over sharp text instead of frosted glass.
hl.layer_rule({
  name = "inua-blur",
  match = { namespace = "^inua-(bar|launcher|control|calendar|passwords|center|banners|dock|drawer|osd|widgets)$" },
  blur = true,
  -- Above the shadows and the control backdrop (under 0.5), below the
  -- surfaces themselves (0.84 and up), so shadows are not blurred.
  ignore_alpha = 0.6,
})

-- The wallpaper should not fade in and out like a window.
hl.layer_rule({
  name = "inua-background",
  match = { namespace = "^inua-background$" },
  no_anim = true,
})

-- The control center, calendar panel, notification center, banners, dock,
-- its drawer, level indicator, launcher and widget page animate themselves.
hl.layer_rule({
  name = "inua-no-anim",
  match = { namespace = "^inua-(launcher|control|calendar|center|banners|dock|drawer|osd|widgets)$" },
  no_anim = true,
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
