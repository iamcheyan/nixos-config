{ config, lib, pkgs, inputs, ... }:

let
  # Nixarchy v4.0.2-4 currently ships an installPhase whose embedded Python
  # check keeps Nix indentation. Unindent the generated shell phase locally;
  # shell indentation is not semantic, while Python indentation is.
  nixarchyPackage = (pkgs.extend inputs.nixarchy.overlays.default).omarchy.overrideAttrs (old: {
    installPhase = lib.replaceStrings [ "\n            " ] [ "\n" ] old.installPhase;
    # The custom SystemSwitch indicator can remain active after a rebuild
    # process exits because Quickshell's process poll is not synchronized with
    # the terminal launcher.  A stale “Rebuilding the system...” spinner is
    # worse than having no indicator; the update command still remains
    # available from the menu and its terminal shows the real build output.
    postInstall = (old.postInstall or "") + ''
      substituteInPlace $out/share/omarchy/shell/plugins/bar/widgets/Indicators.qml \
        --replace-fail \
          '[ "SystemSwitch", "Dictation", "ScreenRecording", "Reminder", "NightLight", "Dnd", "StayAwake" ]' \
          '[ "Dictation", "ScreenRecording", "Reminder", "NightLight", "Dnd", "StayAwake" ]'
      rm -f $out/share/omarchy/shell/plugins/bar/indicators/SystemSwitch.qml
      # Keep terminal applications on their explicit monospace fonts while
      # making the built-in Omarchy Shell UI and topbar use the GNOME-style
      # Cantarell family. Nerd Font glyphs still resolve through Qt fallback.
      substituteInPlace $out/share/omarchy/shell/Commons/Style.qml \
        --replace-fail \
          'property string fontFamily: "monospace"' \
          'property string fontFamily: "Cantarell"'

      # Match the heavier GNOME Shell appearance for readable bar labels.
      # Keep icon glyphs in the same family so Nerd Font fallback remains intact.
      newline="$(printf '\nX')"
      newline="''${newline%X}"
      substituteInPlace $out/share/omarchy/shell/Ui/WidgetButton.qml \
        --replace-fail \
          'font.pixelSize: root.fontSize' \
          "font.pixelSize: root.fontSize''${newline}    font.weight: Font.DemiBold"
      substituteInPlace $out/share/omarchy/shell/plugins/bar/widgets/ActiveWindow.qml \
        --replace-fail \
          'font.pixelSize: Style.font.body' \
          "font.pixelSize: Style.font.body''${newline}      font.weight: Font.DemiBold"

      # A local plugin watcher must never tear down a live session lock. Doing
      # so destroys WlSessionLock while Hyprland is secure and can leave the
      # compositor in its LOCK failsafe, producing a black screen. Defer the
      # reload; after unlocking, a normal shell restart can load the change.
      reload_newline="$(printf '\nX')"
      reload_newline="''${reload_newline%X}"
      reload_guard="  function reloadPlugins() {''${reload_newline}    var lockId = shell.pluginRegistry.resolveEnabledId(\"omarchy.lock\")''${reload_newline}    var lockService = shell.serviceFor(lockId)''${reload_newline}    if (lockService && lockService.locked) {''${reload_newline}      console.warn(\"Deferring plugin reload while session lock is active\")''${reload_newline}      return''${reload_newline}    }"
      substituteInPlace $out/share/omarchy/shell/shell.qml \
        --replace-fail \
          '  function reloadPlugins() {' \
          "$reload_guard"
    '';
  });

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
      runHook postInstall
    '';
  };
in
{
  imports = [
    inputs.nixarchy.nixosModules.nixarchy
    ./fonts.nix
  ];

  # Nixarchy v4.0.2-4 expects this package from nixpkgs, but the pinned
  # NixOS 26.05 branch predates its addition. Keep the stable nixpkgs pin and
  # provide the small compatibility package locally until nixpkgs includes it.
  nixpkgs.overlays = [
    (final: _prev: {
      "hyprland-preview-share-picker" = final.callPackage ./packages/hyprland-preview-share-picker.nix { };
    })
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
    XMODIFIERS = "@im=fcitx";
    QT_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
  };

  # Nixarchy disables Fcitx5's notification-item addon by default because its
  # stock shell does not rely on a traditional tray icon. This desktop keeps
  # an actual tray (`omarchy.tray`), and the input-method indicator is useful
  # to the user, so keep the addon enabled in the generated user service.
  systemd.user.services.omarchy-fcitx5.serviceConfig.ExecStart =
    lib.mkForce "${config.i18n.inputMethod.package}/bin/fcitx5";

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

  programs.nixarchy = {
    enable = true;
    package = nixarchyPackage;
    displayManager = false;
    # Omarchy's update widget and CLI must update the user-owned source flake,
    # not the root-owned compatibility files under /etc/nixos.
    flake = "/home/tetsuya/nixos-config";
  };

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
  services.displayManager.defaultSession = "omarchy";
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "shizuka";
  };
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  programs.hyprland.xwayland.enable = true;
  security.polkit.enable = true;
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

    # Desktop shell / input method / voice
    fish
    librime
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
