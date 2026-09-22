{ config, lib, pkgs, ... }:

let
  cfg = config.programs.labwcPreview;

  # Own the compositor-neutral Quickshell sources in this repository. This is the first
  # migration step away from Nixarchy's packaged Omarchy shell; the current
  # plugins still use NIXARCHY_ROOT for a few helper commands and are kept
  # compatible until those helpers are replaced one by one.
  quickshellRoot = pkgs.runCommand "quickshell-shell" { } ''
    cp -r "${./quickshell}"/. "$out/"
  '';
  # Local compatibility copy of the Omarchy runtime.  Keep the original
  # Nixarchy-provided tree available until the migration has been verified.
  quickshellCompatRoot = pkgs.runCommand "quickshell-omarchy-compat" { } ''
    cp -r "${./quickshell/compat/omarchy}"/. "$out/"
  '';
  quickshellLegacyRoot = "${config.programs.nixarchy.package}/share/omarchy";
  quickshellDevRoot = "/home/tetsuya/nixos-config/modules/quickshell";

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
  labwcCliphist = ./labwc/cliphist;

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
    export QUICKSHELL_OMARCHY_LEGACY_ROOT="${quickshellLegacyRoot}"
    export QUICKSHELL_ROOT="${quickshellRoot}"
    export QUICKSHELL_PLUGINS_DIR="${quickshellRoot}/third-party"
    export QUICKSHELL_CONFIG="$HOME/.config/quickshell/shell.json"
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
    # Reuse the declarative NixOS/Home Manager service instead of launching a
    # second unmanaged fcitx5 process from this script.
    ${pkgs.systemd}/bin/systemctl --user import-environment \
      WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
      XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS \
      QUICKSHELL_ROOT QUICKSHELL_PLUGINS_DIR QUICKSHELL_CONFIG \
      NIXARCHY_ROOT OMARCHY_PATH
    # Refresh systemd's environment for this session's Wayland socket and
    # restart Fcitx5 through the compositor-neutral helper.
    "$HOME/.config/labwc/scripts/nixarchy-import-session-environment" &

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

    # Preserve the user's mutable shell layout while moving it out of the
    # compositor-specific config directory.
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/quickshell"
    if [ ! -e "$HOME/.config/quickshell/shell.json" ] && [ -f "$HOME/.config/labwc/shell.json" ]; then
      ${pkgs.coreutils}/bin/cp "$HOME/.config/labwc/shell.json" "$HOME/.config/quickshell/shell.json"
    fi

    # Supervise only unexpected Quickshell exits.  Re-read the mode on every
    # launch so `quickshell-mode dev` can switch the source without a rebuild.
    while true; do
      quickshell_root="${quickshellRoot}"
      omarchy_root="${quickshellLegacyRoot}"
      if [ -r "$HOME/.config/quickshell/runtime" ] \
        && [ "$(cat "$HOME/.config/quickshell/runtime")" = compat ]; then
        omarchy_root="${quickshellCompatRoot}"
      fi
      if [ -r "$HOME/.config/quickshell/mode" ] \
        && [ "$(cat "$HOME/.config/quickshell/mode")" = dev ] \
        && [ -f "${quickshellDevRoot}/shell.qml" ]; then
        quickshell_root="${quickshellDevRoot}"
      fi
      export NIXARCHY_ROOT="$omarchy_root"
      export OMARCHY_PATH="$omarchy_root"
      export PATH="$omarchy_root/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin:$PATH"
      export QUICKSHELL_ROOT="$quickshell_root"
      export QUICKSHELL_PLUGINS_DIR="$quickshell_root/third-party"
      ${quickshellWithKirigami}/bin/quickshell -n -p "$quickshell_root"
      status=$?
      # A clean exit is also a restart request: labwc -r can tear down the
      # layer-shell client while reloading, and the bar must come back.
      sleep 1
    done &
  '';
in
{
  options.programs.labwcPreview = {
    enable = lib.mkEnableOption "the independent Labwc migration preview";
  };

  config = lib.mkIf cfg.enable {
    programs.labwc.enable = true;

    environment.systemPackages = with pkgs; [
      quickshellWithKirigami
      kdePackages.kirigami
      kdePackages.qqc2-desktop-style
      kdePackages.dolphin
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
      cliphist
      slurp
      tesseract
      swaynotificationcenter
      swayidle
      swaylock
      swaybg
      wdisplays
      wl-clipboard
      wofi
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
      home.file.".local/bin/quickshell-mode" = {
        source = ./labwc/labwc/scripts/quickshell-mode;
        executable = true;
      };
      # Keep a compositor-neutral entry point alongside the historical
      # quickshell-mode helper. Sway/KDE sessions can call the same launcher
      # after importing their own Wayland environment.
      home.file.".local/bin/quickshell-topbar" = {
        source = ./labwc/labwc/scripts/quickshell;
        executable = true;
      };
      home.file.".config/labwc/voxtype-paste.py" = {
        source = ./quickshell/third-party/hancore.voxtype-enhance/scripts/omarchy-universal-paste.py;
        executable = true;
      };
      xdg.configFile."kanshi/config".source = labwcKanshiConfig;
      xdg.configFile."wofi".source = labwcWofi;
      xdg.configFile."fuzzel".source = labwcFuzzel;
      xdg.configFile."mako".source = labwcMako;
      xdg.configFile."cliphist".source = labwcCliphist;
      home.file.".local/share/themes/BL-Lithium-dark".source =
        ./labwc/labwc/themes/BL-Lithium-dark;
      home.file.".local/share/themes/Adwaita-Labwc-dark".source =
        ./labwc/labwc/themes/Adwaita-Labwc-dark;
      xdg.configFile."labwc/autostart" = {
        source = labwcAutostart;
        executable = true;
      };
    };
  };
}
