-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Refresh systemd's environment for whichever Wayland socket this session
-- created before restarting the shared Fcitx5 service.
o.exec_on_start("~/.local/bin/nixarchy-import-session-environment")

-- Ensure default black cursor theme (Adwaita) is applied on startup
o.exec_on_start("hyprctl setcursor Adwaita 24")
