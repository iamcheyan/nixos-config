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
    if [ ! -e "$anchor_state_dir/clipboard-images" ] && [ -d "$legacy_omarchy_state_dir/clipboard-images" ]; then
      ${pkgs.coreutils}/bin/cp -a "$legacy_omarchy_state_dir/clipboard-images" "$anchor_state_dir/clipboard-images"
    fi
    export ANCHOR_SHELL_CONFIG_DIR="$anchor_config_dir"
    export ANCHOR_SHELL_STATE_DIR="$anchor_state_dir"
    export ANCHOR_SHELL_PLUGINS_DIR="$anchor_plugins_dir"
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

    # Supervise only unexpected Quickshell exits.  Re-read the mode on every
    # launch so `quickshell-mode dev` can switch the source without a rebuild.
    while true; do
      quickshell_root="${quickshellRoot}"
      omarchy_root="${quickshellCompatRoot}"
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

    # This service is owned by the compositor-neutral Labwc integration. The
    # Hyprland session keeps its historical omarchy-fcitx5 service separately.
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
        source = ./anchor-shell/third-party/hancore.voxtype-enhance/scripts/omarchy-universal-paste.py;
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
