{ config, lib, pkgs, inputs, ... }:

let
  # Keep the login screen in the system closure so SDDM can discover it under
  # /run/current-system/sw/share/sddm/themes. The source is the locked Shizuka
  # flake input, so new machines do not need a local theme clone or copy.
  shizukaSddmTheme = pkgs.stdenvNoCC.mkDerivation {
    pname = "shizuka-sddm-theme";
    version = inputs.shizuka.rev or "unstable";
    src = inputs.shizuka;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/sddm/themes/shizuka"
      cp -r ./* "$out/share/sddm/themes/shizuka/"
      # Keep Shizuka's optional wallpaper sync helper on the same canonical
      # state file as Labwc, Anchor Shell, and chezmoi.
      substituteInPlace "$out/share/sddm/themes/shizuka/scripts/sync-wallpaper-to-sddm.sh" \
        --replace-fail \
          'state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"' \
          'state_file="''${SHIZUKA_WALLPAPER_STATE:-''${ANCHOR_SHELL_STATE_DIR:-''${XDG_STATE_HOME:-$HOME/.local/state}/anchor-shell}/wallpaper}"' \
        --replace-fail \
          'background_link="''${SHIZUKA_OMARCHY_BACKGROUND:-$state_home/omarchy/current/background}"' \
          'background="$(cat "$state_file" 2>/dev/null || true)"' \
        --replace-fail \
          'background="$(readlink -f "$background_link" 2>/dev/null || true)"' \
          ':'
      # Display login controls and interactions only on the primary screen.
      # Secondary displays render a clean blurred wallpaper. Adapt scaling
      # dynamically and keep elements centered on the primary display.
      ${pkgs.python3}/bin/python3 -c "
with open('$out/share/sddm/themes/shizuka/Main.qml', 'r') as f:
    text = f.read()

if 'readonly property bool isPrimary:' not in text:
    text = text.replace(
        'property bool previewMode: Qt.application.arguments.indexOf(\"--test-mode\") >= 0',
        'property bool previewMode: Qt.application.arguments.indexOf(\"--test-mode\") >= 0\n    readonly property bool isPrimary: typeof primaryScreen !== \"undefined\" ? primaryScreen : true'
    )
    text = text.replace('focus: true', 'focus: root.isPrimary')
    text = text.replace(
        'model: userModel',
        'model: root.isPrimary ? userModel : null'
    )
    text = text.replace(
        'showPasswordInput() {\n        root.passwordVisible',
        'showPasswordInput() {\n        if (!root.isPrimary) return;\n        root.passwordVisible'
    )
    text = text.replace(
        'handlePasswordShortcut(event) {\n        if (event.key === Qt.Key_Escape)',
        'handlePasswordShortcut(event) {\n        if (!root.isPrimary) return;\n        if (event.key === Qt.Key_Escape)'
    )
    text = text.replace(
        'function login() {\n        if (root.authenticating',
        'function login() {\n        if (!root.isPrimary || root.authenticating'
    )
    text = text.replace(
        'Connections {\n        target: sddm',
        'Connections {\n        target: sddm\n        enabled: root.isPrimary'
    )
    text = text.replace(
        'Timer {\n        interval: 1000\n        repeat: true\n        running: true',
        'Timer {\n        interval: 1000\n        repeat: true\n        running: root.isPrimary'
    )
    text = text.replace(
        'Keys.priority: Keys.BeforeItem\n    Keys.onPressed: function(event) { root.handlePasswordShortcut(event) }',
        'Keys.enabled: root.isPrimary\n    Keys.priority: Keys.BeforeItem\n    Keys.onPressed: function(event) { if (root.isPrimary) root.handlePasswordShortcut(event) }'
    )
    text = text.replace(
        'Column {\n        anchors.top: parent.top',
        'Column {\n        visible: root.isPrimary\n        anchors.top: parent.top'
    )
    text = text.replace(
        'Controls.ComboBox {\n        id: sessionBox',
        'Controls.ComboBox {\n        id: sessionBox\n        visible: root.isPrimary'
    )
    text = text.replace(
        'Controls.ComboBox {\n        id: powerBox',
        'Controls.ComboBox {\n        id: powerBox\n        visible: root.isPrimary'
    )

text = text.replace(
    'readonly property real screenWidth: Math.max(1, root.screenGeometry.width || root.width)',
    'readonly property real screenWidth: Math.max(1, root.width > 0 ? root.width : root.screenGeometry.width)'
)
text = text.replace(
    'readonly property real screenHeight: Math.max(1, root.screenGeometry.height || root.height)',
    'readonly property real screenHeight: Math.max(1, root.height > 0 ? root.height : root.screenGeometry.height)'
)
for old_scale in [
    'property real uiScale: Math.max(0.72, Math.min(1.0,',
    'property real uiScale: Math.max(0.72, Math.min(1.35,'
]:
    text = text.replace(old_scale, 'property real uiScale: Math.max(0.5, Math.min(2.5,')

old_login = '    Column {\n        anchors.bottom: parent.bottom\n        anchors.bottomMargin: Math.max(px(48), parent.height * 0.07)'
new_login = '    Column {\n        visible: root.isPrimary\n        anchors.centerIn: parent\n        anchors.verticalCenterOffset: Math.max(px(8), parent.height * 0.02)'
text = text.replace(old_login, new_login)

# Recovery mode for a greeter compositor that reports no usable primary
# output: keep the login controls visible and interactive so the user can
# enter the desktop and repair the output layout from the real session.
text = text.replace('visible: root.isPrimary', 'visible: true')
text = text.replace('model: root.isPrimary ? userModel : null', 'model: userModel')
text = text.replace('if (!root.isPrimary) return;', ' ')
text = text.replace('if (!root.isPrimary || root.authenticating', 'if (root.authenticating')
text = text.replace('enabled: root.isPrimary', 'enabled: true')
text = text.replace('running: root.isPrimary', 'running: true')
text = text.replace(
    'Keys.onPressed: function(event) { if (root.isPrimary) root.handlePasswordShortcut(event) }',
    'Keys.onPressed: function(event) { root.handlePasswordShortcut(event) }'
)

with open('$out/share/sddm/themes/shizuka/Main.qml', 'w') as f:
    f.write(text)
"
      runHook postInstall
    '';
  };

  # NixOS 26.05's Qt6 SDDM wrapper exposes only sddm-greeter-qt6, while
  # SDDM's custom-theme compatibility check still looks for sddm-greeter.
  # Keep the Qt6 greeter and provide the legacy name as a local alias so the
  # Shizuka theme is actually loaded instead of silently falling back.
  sddmUnwrappedQt6Compat = pkgs.kdePackages.sddm.unwrapped.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      ln -sf sddm-greeter-qt6 $out/bin/sddm-greeter
    '';
  });
  sddmQt6Compat = pkgs.kdePackages.sddm.override {
    sddm-unwrapped = sddmUnwrappedQt6Compat;
  };
in
{
  imports = [
    ./desktop-runtime.nix
    ./fonts.nix
  ];


  # Desktop hosts own networking, audio, printing, fonts, and graphical tools.
  networking.networkmanager.enable = true;
  services.printing.enable = true;
  nixpkgs.config.allowUnfree = true;

  security.sudo.extraRules = [
    {
      users = [ "tetsuya" ];
      commands = [ { command = "ALL"; options = [ "NOPASSWD" "SETENV" ]; } ];
    }
  ];

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-rime
      librime
      fcitx5-gtk
      qt6Packages.fcitx5-configtool
    ];
  };

  environment.sessionVariables = {
    QT_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
  };

  # Keep Fcitx5's notification-item addon enabled for the desktop tray.
  systemd.user.services.omarchy-fcitx5.serviceConfig.ExecStart =
    lib.mkForce "${config.i18n.inputMethod.package}/bin/fcitx5";

  # Compositors create a different Wayland socket (and may use a different
  # desktop name) on each login.  Keep the user service generic and let the
  # active compositor refresh systemd's environment at session startup.
  home-manager.users.tetsuya.home.file.".local/bin/desktop-import-session-environment" = {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      [[ -n "''${WAYLAND_DISPLAY:-}" ]] || exit 0
      ${pkgs.systemd}/bin/systemctl --user import-environment \
        WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
        XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS
      ${pkgs.systemd}/bin/systemctl --user restart --no-block omarchy-fcitx5.service
    '';
  };

  services.logind.settings.Login = {
    IdleAction = "ignore";
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };
  boot.kernel.sysctl."vm.swappiness" = 180;


  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.xserver.enable = true;
  services.displayManager.defaultSession = "labwc";
  services.displayManager.sddm = {
    enable = true;
    package = lib.mkForce sddmQt6Compat;
    wayland.enable = true;
    theme = "shizuka";
    # Use a revision-specific URL: /run/current-system is stable across
    # rebuilds and Nix normalizes mtimes, so Qt can reuse stale QML bytecode.
    settings.Theme.ThemeDir = "${shizukaSddmTheme}/share/sddm/themes";
  };
  services.desktopManager.plasma6.enable = true;
  # DrKonqi crashes when handling coredumps outside full Plasma sessions (e.g. Labwc)
  # and litters failed systemd units. Disable systemd coredump hooks for DrKonqi.
  systemd.services."drkonqi-coredump-processor@".enable = false;
  systemd.user.services."drkonqi-coredump-launcher@".enable = false;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  security.polkit.enable = true;
  # The Windows VM helper deliberately writes its compose file as root through
  # pkexec. Authorize only this root-owned, immutable Omarchy helper for the
  # local desktop user so installation does not depend on an interactive
  # password dialog. This does not authorize arbitrary pkexec programs.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      var program = action.lookup("program");
      if (action.id == "org.freedesktop.policykit.exec" &&
          subject.user == "tetsuya" &&
          subject.local == true &&
          subject.active == true &&
          program != null &&
          /\/share\/omarchy\/bin\/omarchy-windows-vm$/.test(program)) {
        return polkit.Result.YES;
      }
    });
  '';
  services.gnome.gnome-keyring.enable = true;
  services.power-profiles-daemon.enable = true;
  programs.dconf.enable = true;

  # Desktop utilities and graphical tools for the Hyprland/Omarchy session.
  # Common CLI and development tools are provided by cli.nix and dev.nix.
  environment.systemPackages = with pkgs; [
    shizukaSddmTheme

    # Desktop terminals and GUI applications
    kitty
    alacritty
    ghostty
    foot
    firefox
    nautilus

    # KDE applications used from Labwc need their dark widget style, color
    # scheme, and icon theme available outside a Plasma session as well.
    kdePackages.breeze
    kdePackages.breeze-icons

    # Desktop shell / input method / voice
    fish
    # Henri desktop-icons uses Gio/GLib through PyGObject for safe file and
    # trash operations. Keep the dependency in the declarative system path.
    (python3.withPackages (ps: [ ps.pygobject3 ]))
    librime
    telegram-desktop
    voxtype-onnx

    # Linux system utilities, compilers & sandboxing
    man-db
    bubblewrap
    podman
    sshfs
    gcc
    dotnet-sdk_9
    node-gyp

    # Wayland / desktop automation tools
    wlr-randr
    grim
    slurp
    swappy
    wl-clipboard
    xclip
    xdotool
    wtype
    ydotool
    brightnessctl
    pamixer
  ];

  systemd.services.amdgpu-dpm = {
    description = "Pin amdgpu DPM performance level (AC=high, battery=auto)";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.bash ];
    script = ''
      level=auto
      if grep -q 1 /sys/class/power_supply/A*/online 2>/dev/null; then
        level=high
      fi
      for f in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
        printf '%s' "$level" > "$f" 2>/dev/null || true
      done
    '';
  };
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", \
      TAG+="systemd", ENV{SYSTEMD_WANTS}+="amdgpu-dpm.service"
  '';
}
