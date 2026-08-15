{ config, pkgs, ... }:

{
  # 1. Bluetooth support
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # 2. Sound configuration via Pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # 3. X server + SDDM display manager (login screen)
  services.xserver.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  # Default to the plain Hyprland session (start-hyprland, no uwsm) —
  # the uwsm-managed session fails to start its bindpid unit here.
  services.displayManager.defaultSession = "sumika-shell";

  # Use KDE Breeze as the SDDM login theme.
  # Requires the Plasma desktop environment to be enabled so its KDE QML
  # modules (org.kde.breeze.components, kirigami, plasma.components) are on
  # the SDDM greeter's QML import path; otherwise the theme fails to load.
  services.displayManager.sddm.theme = "breeze";
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # 4. Hyprland & Portal core desktop
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
  };

  # 5. Polkit and security services
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  services.power-profiles-daemon.enable = true;
  programs.dconf.enable = true;

  # 6. Core fonts pack
  fonts.packages = with pkgs; [
    cantarell-fonts
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
    meslo-lgs-nf
    material-symbols
    font-awesome
  ];

  # 7. Oh-My-Desktop desktop session definition (for SDDM / GDM login manager)
  services.displayManager.sessionPackages = [
    (pkgs.stdenvNoCC.mkDerivation {
      pname = "sumika-shell-session";
      version = "1";
      dontUnpack = true;
      passthru.providedSessions = [ "sumika-shell" ];
      installPhase = ''
        mkdir -p $out/bin $out/share/wayland-sessions
        cp ${pkgs.writeShellScript "omd-hyprland-session" ''
          export SUMIKA_SHELL_ROOT="''${HOME}/development/OMD"
          export SUMIKA_FORCE_NO_UWSM=1
          export XDG_CURRENT_DESKTOP=Hyprland
          export XDG_SESSION_DESKTOP=sumika-shell
          export XDG_SESSION_TYPE=wayland
          export QT_QPA_PLATFORM=wayland
          export GDK_BACKEND=wayland,x11
          export MOZ_ENABLE_WAYLAND=1
          export PATH="''${HOME}/.local/bin:''${SUMIKA_SHELL_ROOT}/bin:${pkgs.hyprland}/bin:${pkgs.quickshell}/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin:/run/current-system/sw/bin:''${PATH}"

          config="''${SUMIKA_SHELL_ROOT}/hypr/hyprland.lua"
          if [[ ! -f "$config" ]]; then
            echo "OMD Hyprland config not found: $config" >&2
            exit 1
          fi

          if [[ -x ${pkgs.hyprland}/bin/start-hyprland ]]; then
            exec ${pkgs.hyprland}/bin/start-hyprland -- -c "$config"
          fi

          exec ${pkgs.hyprland}/bin/Hyprland -c "$config"
        ''} $out/bin/omd-hyprland-session
        printf '%s\n' \
          '[Desktop Entry]' \
          'Name=Sumika Shell' \
          'Comment=Sumika Shell Hyprland session with Quickshell' \
          "Exec=$out/bin/omd-hyprland-session" \
          'Type=Application' \
          'DesktopNames=Hyprland' \
          'Keywords=tiling;wayland;compositor;' \
          > $out/share/wayland-sessions/sumika-shell.desktop
      '';
    })
  ];

  # 8. Desktop-specific applications and tool packages
  environment.systemPackages = with pkgs; [
    # Provides the KDE Breeze SDDM login theme (services.displayManager.sddm.theme)
    kdePackages.plasma-desktop

    # OMD / Hyprland Core Packages
    hyprpicker
    xdg-desktop-portal-hyprland
    quickshell
    walker
    cliphist
    wl-clipboard
    mako

    # Audio, display, screenshot, power and session tools
    pamixer
    playerctl
    pavucontrol
    pulseaudio
    networkmanagerapplet
    brightnessctl
    swaybg
    wlr-randr
    grim
    slurp
    swappy
    ydotool
    libqalculate
    imagemagick
    power-profiles-daemon
    gnome-keyring
    polkit_gnome

    # Terminals
    foot
    kitty

    # Qt/GTK integration and file/media tools
    kdePackages.qtwayland
    kdePackages.qt5compat      # Qt5Compat.GraphicalEffects QML module for Quickshell
    kdePackages.qt6ct
    kdePackages.qtstyleplugin-kvantum
    adwaita-qt
    gnome-themes-extra
    xdg-desktop-portal-gtk
    zenity
    nautilus
    evince
    kdePackages.plasma-systemmonitor
    bluez
  ];
}
