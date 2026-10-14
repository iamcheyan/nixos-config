-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Refresh systemd's environment for whichever Wayland socket this session
-- created before restarting the shared Fcitx5 service.
o.exec_on_start("~/.local/bin/desktop-import-session-environment")

-- The Inua login entry reuses this Hyprland configuration and starts its
-- shell only for that session.
if os.getenv("INUA_SESSION") == "1" then
  o.exec_on_start("inua-shell")
end

-- Ensure default black cursor theme (Adwaita) is applied on startup
o.exec_on_start("hyprctl setcursor Adwaita 24")
