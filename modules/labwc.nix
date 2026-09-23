{ config, lib, pkgs, ... }:

let
  cfg = config.programs.labwcPreview;

  # Own the compositor-neutral Quickshell sources in this repository. This is the first
  # migration step away from Nixarchy's packaged Omarchy shell; the current
  # plugins still use NIXARCHY_ROOT for a few helper commands and are kept
  # compatible until those helpers are replaced one by one.
  quickshellRoot = pkgs.runCommand "anchor-shell" { } ''
    cp -r "${./anchor-shell}"/. "$out/"
  '';
  # Local compatibility copy of the historical Omarchy runtime. Labwc uses
  # this repository-owned tree directly; it must not fall back to the
  # Nixarchy-provided package used by the separate Hyprland session.
  quickshellCompatRoot = pkgs.runCommand "anchor-shell-omarchy-compat" { } ''
    cp -r "${./anchor-shell/compat/omarchy}"/. "$out/"
  '';
  quickshellDevRoot = "/home/tetsuya/nixos-config/modules/anchor-shell";
  # Henri desktop-icons uses Gio/GLib through PyGObject. Keep its interpreter
  # isolated instead of changing the system's generic python3 selection.
  anchorShellPython = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  anchorAddToDesktop = pkgs.writeShellScriptBin "add-to-desktop" ''
    exec ${anchorShellPython}/bin/python3 \
      ${quickshellRoot}/plugins/desktop-icons/bin/add-to-desktop "$@"
  '';
  anchorSetWallpaper = pkgs.writeShellScriptBin "labwc-set-wallpaper" ''
    exec "$HOME/.config/labwc/scripts/set-wallpaper-image" "$@"
  '';

  # Quickshell's Qt wrapper only exports its own QML modules. The Omarchy
  # right-side widgets use Breeze controls, which import KDE Kirigami; expose
  # that module explicitly for both the immutable and dev source modes.
  quickshellWithKirigami = lib.hiPrio (pkgs.writeShellScriptBin "quickshell" ''
    export QT_QUICK_CONTROLS_STYLE=Basic
    export QML2_IMPORT_PATH="${pkgs.kdePackages.kirigami.unwrapped}/lib/qt-6/qml''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
    export QML_IMPORT_PATH="${pkgs.kdePackages.kirigami.unwrapped}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
    exec ${pkgs.quickshell}/bin/quickshell "$@"
  '');

  # Power actions become searchable desktop entries in the Wofi launcher
  # opened by Win+Space. Hibernate is copied only when the kernel supports it.
  powerDesktopFiles = {
    logout = pkgs.writeText "nixarchy-logout.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=Log Out
      Comment=End the current desktop session
      Icon=system-log-out
      Exec=${./labwc/labwc/scripts/system-menu} logout
      Terminal=false
      Categories=System;
    '';
    suspend = pkgs.writeText "nixarchy-suspend.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=Suspend
      Comment=Suspend the computer
      Icon=system-suspend
      Exec=${./labwc/labwc/scripts/system-menu} suspend
      Terminal=false
      Categories=System;
    '';
    hibernate = pkgs.writeText "nixarchy-hibernate.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=Hibernate
      Comment=Hibernate the computer
      Icon=system-hibernate
      Exec=${./labwc/labwc/scripts/system-menu} hibernate
      Terminal=false
      Categories=System;
    '';
    reboot = pkgs.writeText "nixarchy-reboot.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=Restart
      Comment=Restart the computer
      Icon=system-reboot
      Exec=${./labwc/labwc/scripts/system-menu} reboot
      Terminal=false
      Categories=System;
    '';
    shutdown = pkgs.writeText "nixarchy-shutdown.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=Shut Down
      Comment=Power off the computer
      Icon=system-shutdown
      Exec=${./labwc/labwc/scripts/system-menu} poweroff
      Terminal=false
      Categories=System;
    '';
  };

  # Labwc configuration and asset sources managed declaratively.
  labwcConfig = ./labwc/labwc/rc.xml;
  labwcMenu = ./labwc/labwc/menu.xml;
  labwcEnvironment = ./labwc/labwc/environment;
  labwcKeyboardEnvironment = ./labwc/labwc/environment.d/90-keyboard.env;
  labwcKeybinds = ./labwc/labwc/keybinds;
  labwcWofi = ./labwc/wofi;
  labwcFuzzel = ./labwc/fuzzel;
  labwcMako = ./labwc/mako;
  labwcThemeRoot = ./labwc/labwc/themes;
  labwcThemeNames = builtins.attrNames (lib.filterAttrs
    (name: type:
      type == "directory"
      && builtins.pathExists (labwcThemeRoot + "/${name}/openbox-3/themerc"))
    (builtins.readDir labwcThemeRoot));

  # Keep the Philips display as the 1x primary output and render the 4K
  # secondary display at 2x HiDPI.  Positions are in logical pixels, so the
  # 1280px-wide Philips output is followed directly by the 1920px-wide
  # logical area of the scaled 4K output.
  labwcKanshiConfig = pkgs.writeText "labwc-kanshi.conf" ''
    profile {
      output HDMI-A-1 mode 1280x1024@60Hz position 0,0 scale 1
      output HDMI-A-2 mode 3840x2160@60Hz position 1280,0 scale 2
    }
  '';

  labwcAutostart = pkgs.writeText "labwc-autostart" ''
    # Labwc starts this file only for the Labwc session.  The regular Omarchy
    # launcher remains responsible for the Hyprland session.
    export QUICKSHELL_OMARCHY_COMPAT_ROOT="${quickshellCompatRoot}"
    anchor_config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/anchor-shell"
    anchor_state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/anchor-shell"
    anchor_plugins_dir="$anchor_config_dir/plugins"
    legacy_config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
    legacy_omarchy_config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
    legacy_omarchy_state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
    ${pkgs.coreutils}/bin/mkdir -p "$anchor_config_dir" "$anchor_plugins_dir" "$anchor_state_dir"
    # Migrate user-owned state once, without deleting or changing the legacy
    # tree.  The old files remain available to the Hyprland session.
    for file in shell.json shell.toml lock-screen.json; do
      if [ ! -e "$anchor_config_dir/$file" ] && [ -f "$legacy_omarchy_config_dir/$file" ]; then
        ${pkgs.coreutils}/bin/cp "$legacy_omarchy_config_dir/$file" "$anchor_config_dir/$file"
      fi
    done
    if [ ! -e "$anchor_config_dir/shell.json" ] && [ -f "$legacy_config_dir/shell.json" ]; then
      ${pkgs.coreutils}/bin/cp "$legacy_config_dir/shell.json" "$anchor_config_dir/shell.json"
    fi
    for subdir in themes backgrounds themed; do
      if [ ! -e "$anchor_config_dir/$subdir" ] && [ -d "$legacy_omarchy_config_dir/$subdir" ]; then
        ${pkgs.coreutils}/bin/cp -a "$legacy_omarchy_config_dir/$subdir" "$anchor_config_dir/$subdir"
      fi
    done
    for subdir in current notifications settings toggles indicators; do
      if [ ! -e "$anchor_state_dir/$subdir" ] && [ -d "$legacy_omarchy_state_dir/$subdir" ]; then
        ${pkgs.coreutils}/bin/cp -a "$legacy_omarchy_state_dir/$subdir" "$anchor_state_dir/$subdir"
      fi
    done
    for file in clipboard-history.json clipboard-theme.json; do
      if [ ! -e "$anchor_state_dir/$file" ] && [ -f "$legacy_omarchy_state_dir/$file" ]; then
        ${pkgs.coreutils}/bin/cp "$legacy_omarchy_state_dir/$file" "$anchor_state_dir/$file"
      fi
    done
    if [ ! -e "$anchor_state_dir/desktop-icon-positions.json" ] \
      && [ -f "$legacy_omarchy_config_dir/desktop-icon-positions.json" ]; then
      ${pkgs.coreutils}/bin/cp "$legacy_omarchy_config_dir/desktop-icon-positions.json" \
        "$anchor_state_dir/desktop-icon-positions.json"
    fi
    if [ ! -e "$anchor_state_dir/clipboard-images" ] && [ -d "$legacy_omarchy_state_dir/clipboard-images" ]; then
      ${pkgs.coreutils}/bin/cp -a "$legacy_omarchy_state_dir/clipboard-images" "$anchor_state_dir/clipboard-images"
    fi
    export ANCHOR_SHELL_CONFIG_DIR="$anchor_config_dir"
    export ANCHOR_SHELL_STATE_DIR="$anchor_state_dir"
    export ANCHOR_SHELL_PLUGINS_DIR="$anchor_plugins_dir"
    export ANCHOR_SHELL_PYTHON="${anchorShellPython}/bin/python3"
    export QUICKSHELL_ROOT="${quickshellRoot}"
    export QUICKSHELL_PLUGINS_DIR="$anchor_plugins_dir"
    export QUICKSHELL_CONFIG="$anchor_config_dir/shell.json"
    export XDG_CURRENT_DESKTOP=labwc
    export XDG_SESSION_DESKTOP=labwc
    export QT_QUICK_CONTROLS_STYLE=Basic
    export QML2_IMPORT_PATH="${pkgs.kdePackages.kirigami.unwrapped}/lib/qt-6/qml''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
    export QML_IMPORT_PATH="${pkgs.kdePackages.kirigami.unwrapped}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"

    # Apply output modes, positions, and scale on login and on hotplug.
    ${pkgs.kanshi}/bin/kanshi -c "${labwcKanshiConfig}" >/dev/null 2>&1 &

    # Labwc owns the desktop wallpaper via set-wallpaper script.
    "$HOME/.config/labwc/scripts/set-wallpaper" wayland >/dev/null 2>&1 &

    # Labwc does not necessarily activate graphical-session.target itself.
    # Reuse the Labwc-owned declarative service instead of launching an
    # unmanaged fcitx5 process from this script.
    ${pkgs.systemd}/bin/systemctl --user import-environment \
      WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
      XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
      ANCHOR_SHELL_CONFIG_DIR ANCHOR_SHELL_STATE_DIR ANCHOR_SHELL_PLUGINS_DIR \
      QUICKSHELL_ROOT QUICKSHELL_PLUGINS_DIR QUICKSHELL_CONFIG \
      ANCHOR_SHELL_PYTHON \
      NIXARCHY_ROOT OMARCHY_PATH
    # Refresh the Labwc-owned Fcitx5 service for this session's Wayland socket.
    ${pkgs.systemd}/bin/systemctl --user restart --no-block anchor-fcitx5.service &

    # Win+Space opens Wofi's desktop-entry launcher in Labwc. Keep power actions
    # there, and expose Hibernate only when the kernel supports `disk`.
    power_applications="$HOME/.local/share/applications"
    ${pkgs.coreutils}/bin/mkdir -p "$power_applications"
    ${pkgs.coreutils}/bin/cp -f --no-preserve=mode "${powerDesktopFiles.logout}" "$power_applications/nixarchy-logout.desktop"
    ${pkgs.coreutils}/bin/cp -f --no-preserve=mode "${powerDesktopFiles.suspend}" "$power_applications/nixarchy-suspend.desktop"
    ${pkgs.coreutils}/bin/cp -f --no-preserve=mode "${powerDesktopFiles.reboot}" "$power_applications/nixarchy-reboot.desktop"
    ${pkgs.coreutils}/bin/cp -f --no-preserve=mode "${powerDesktopFiles.shutdown}" "$power_applications/nixarchy-shutdown.desktop"
    if ${pkgs.gnugrep}/bin/grep -qw disk /sys/power/state 2>/dev/null; then
      ${pkgs.coreutils}/bin/cp -f --no-preserve=mode "${powerDesktopFiles.hibernate}" "$power_applications/nixarchy-hibernate.desktop"
    else
      ${pkgs.coreutils}/bin/rm -f "$power_applications/nixarchy-hibernate.desktop"
    fi

    # labwc does not reliably activate graphical-session.target.  Voxtype may
    # therefore have been started before the Wayland session and before the
    # Quickshell IPC environment was imported; restart it so the paste hook
    # can identify the current application on every compositor.
    ${pkgs.systemd}/bin/systemctl --user restart --no-block voxtype.service &

    ${pkgs.mako}/bin/mako &

    # Anchor Shell is supervised by the user systemd service below.  Keep
    # exactly one owner for the Quickshell process; a second shell here can
    # race the IPC/layer-shell instance and leave labwc looking black.
    ${pkgs.systemd}/bin/systemctl --user restart --no-block anchor-shell-labwc-probe.service &
  '';
in
{
  options.programs.labwcPreview = {
    enable = lib.mkEnableOption "the independent Labwc migration preview";
  };

  config = lib.mkIf cfg.enable {
    programs.labwc.enable = true;

    # This service is owned by the compositor-neutral Labwc integration. The
    # Hyprland session keeps its historical omarchy-fcitx5 service separately.
    # Anchor Shell owns the Quickshell layer in Labwc.  It is started by
    # labwc/autostart after the session environment has been imported and is
    # restarted only by systemd when the process exits.
    systemd.user.services.anchor-shell-labwc-probe = {
      description = "Anchor Shell for the Labwc session";
      serviceConfig = {
        ExecStart = "${quickshellWithKirigami}/bin/quickshell -n -p ${quickshellRoot}";
        Environment = [
          "PATH=/run/current-system/sw/bin:/run/wrappers/bin:/bin"
          "NIXARCHY_ROOT=${quickshellCompatRoot}"
          "OMARCHY_PATH=${quickshellCompatRoot}"
          "QUICKSHELL_ROOT=${quickshellRoot}"
          "QUICKSHELL_PLUGINS_DIR=${quickshellRoot}/plugins"
          "QUICKSHELL_CONFIG=%h/.config/anchor-shell/shell.json"
          "ANCHOR_SHELL_CONFIG_DIR=%h/.config/anchor-shell"
          "ANCHOR_SHELL_STATE_DIR=%h/.local/state/anchor-shell"
          "ANCHOR_SHELL_PLUGINS_DIR=%h/.config/anchor-shell/plugins"
          "XDG_CURRENT_DESKTOP=labwc"
          "XDG_SESSION_DESKTOP=labwc"
        ];
        Restart = "always";
        RestartSec = 1;
      };
    };

    systemd.user.services.anchor-fcitx5 = {
      description = "Fcitx5 input method for Anchor Shell sessions";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
      serviceConfig = {
        ExecStart = "${config.i18n.inputMethod.package}/bin/fcitx5";
        Restart = "always";
        RestartSec = 2;
        Type = "simple";
      };
    };

    environment.systemPackages = with pkgs; [
      quickshellWithKirigami
      kdePackages.kirigami
      kdePackages.qqc2-desktop-style
      kdePackages.dolphin
      anchorAddToDesktop
      anchorSetWallpaper
      foot
      fuzzel
      grim
      gpu-screen-recorder
      kanshi
      mako
      networkmanagerapplet
      nwg-look
      pavucontrol
      playerctl
      bc
      slurp
      tesseract
      wdisplays
      wl-clipboard
      wofi
      wbg
      wlr-randr
      zbar
    ];

    home-manager.users.tetsuya = {
      xdg.configFile."labwc/rc.xml".source = labwcConfig;
      xdg.configFile."labwc/menu.xml".source = labwcMenu;
      xdg.configFile."labwc/environment".source = labwcEnvironment;
      xdg.configFile."labwc/environment.d/90-keyboard.env".source = labwcKeyboardEnvironment;
      xdg.configFile."labwc/keybinds".source = labwcKeybinds;
      xdg.configFile."labwc/scripts".source = ./labwc/labwc/scripts;
      home.file = lib.genAttrs
        (map (name: ".local/share/themes/${name}") labwcThemeNames)
        (target: {
          source = labwcThemeRoot + "/${lib.removePrefix ".local/share/themes/" target}";
        }) // {
          ".local/bin/quickshell-mode" = {
            source = ./labwc/labwc/scripts/quickshell-mode;
            executable = true;
          };
          # Keep a compositor-neutral entry point alongside the historical
          # quickshell-mode helper. Sway/KDE sessions can call the same launcher
          # after importing their own Wayland environment.
          ".local/bin/quickshell-topbar" = {
            source = ./labwc/labwc/scripts/quickshell;
            executable = true;
          };
          ".config/labwc/voxtype-paste.py" = {
            source = ./anchor-shell/plugins/voxtype/scripts/omarchy-universal-paste.py;
            executable = true;
          };
      };
      xdg.configFile."kanshi/config".source = labwcKanshiConfig;
      xdg.configFile."wofi".source = labwcWofi;
      xdg.configFile."fuzzel".source = labwcFuzzel;
      xdg.configFile."mako".source = labwcMako;
      xdg.dataFile."kio/servicemenus/anchor-send-to-desktop.desktop" = {
        source = ./anchor-shell/plugins/desktop-icons/dolphin/send-to-desktop.desktop;
        executable = true;
      };
      xdg.dataFile."kio/servicemenus/labwc-set-wallpaper.desktop" = {
        source = ./labwc/dolphin/set-wallpaper.desktop;
        executable = true;
      };
      xdg.configFile."labwc/autostart" = {
        source = labwcAutostart;
        executable = true;
      };
    };
  };
}
