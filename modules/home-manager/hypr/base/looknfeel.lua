-- Base look and behaviour for the Hyprland session.
--
-- Carried here from Omarchy's default.hypr.looknfeel now that the Hyprland
-- session no longer loads Omarchy's modules. This file loads before
-- hypr/looknfeel.lua, which overrides gaps, borders and animations to the
-- personal "practical mode" (no gaps, no animation, opaque windows). What is
-- kept here is what that override does not touch: border colours, the layout
-- engines and the misc/cursor/binds behaviour.
--
-- https://wiki.hypr.land/Configuring/Basics/Variables/

local active_border_color = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }
local inactive_border_color = "rgba(595959aa)"

hl.config({
  general = {
    border_size = 2,

    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },

    allow_tearing = false,
    layout = "dwindle",
  },

  decoration = {
    rounding = 0,
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },

    groupbar = {
      font_size = 12,
      font_family = "monospace",
      font_weight_active = "ultraheavy",
      font_weight_inactive = "normal",
      indicator_height = 1,
      indicator_gap = 5,
      height = 22,
      gaps_in = 5,
      gaps_out = 0,
      text_color = "rgb(ffffff)",
      text_color_inactive = "rgba(ffffff90)",
      col = {
        active = "rgba(00000040)",
        inactive = "rgba(00000020)",
      },
      gradients = true,
      gradient_rounding = 0,
      gradient_round_only_edges = false,
    },
  },
})

hl.config({
  dwindle = {
    preserve_split = true,
    force_split = 2,
  },

  scrolling = {
    column_width = 0.49,
  },

  master = {
    new_status = "master",
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    disable_scale_notification = true,
    focus_on_activate = true,
    anr_missed_pings = 3,
    on_focus_under_fullscreen = 1,
    initial_workspace_tracking = 0,
    -- Let a fresh shell re-acquire the session lock after the lock client
    -- died, so a shell restart can recover the lock failsafe.
    allow_session_lock_restore = true,
  },

  cursor = {
    hide_on_key_press = true,
    warp_on_change_workspace = 1,
  },

  binds = {
    hide_special_on_workspace_change = true,
  },
})
