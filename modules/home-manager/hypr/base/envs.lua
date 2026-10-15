-- Wayland and toolkit environment for the Hyprland session.
--
-- Carried here from Omarchy's default.hypr.envs now that the Hyprland session
-- no longer loads Omarchy's modules. The compositor does not define these on
-- its own, and without them GTK/Qt/Firefox/Electron apps fall back to X11.

-- Cursor size.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force applications onto Wayland.
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Screen sharing (Google Meet, Discord, browser calls) reads the desktop name
-- to select the right portal backend.
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- XCompose: fcitx5 and GTK read this for compose sequences. The file itself is
-- written at login by the desktop seed activation.
hl.env("XCOMPOSEFILE", (os.getenv("HOME") or "") .. "/.XCompose")

hl.config({
  xwayland = {
    force_zero_scaling = true,
  },

  ecosystem = {
    no_update_news = true,
  },
})
