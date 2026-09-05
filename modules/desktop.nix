{ config, lib, pkgs, inputs, ... }:

let
  # Nixarchy v4.0.2-4 currently ships an installPhase whose embedded Python
  # check keeps Nix indentation. Unindent the generated shell phase locally;
  # shell indentation is not semantic, while Python indentation is.
  nixarchyPackage = (pkgs.extend inputs.nixarchy.overlays.default).omarchy.overrideAttrs (old: {
    installPhase = lib.replaceStrings [ "\n            " ] [ "\n" ] old.installPhase;
  });
in
{
  imports = [ inputs.nixarchy.nixosModules.nixarchy ];

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
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "breeze";
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

  fonts.packages = with pkgs; [
    adwaita-fonts
    cantarell-fonts
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
    meslo-lgs-nf
    material-symbols
    font-awesome
  ];

  # Desktop utilities used by the Hyprland/Omarchy session and user services.
  # Keep these in the NixOS system layer so a fresh machine has the complete
  # graphical baseline before chezmoi applies user-level orchestration.
  environment.systemPackages = with pkgs; [
    # Desktop terminal/file tools; not installed in the WSL host.
    kitty
    alacritty
    ghostty
    foot
    yazi
    zellij
    ranger
    firefox
    librime
    fish
    starship
    age
    bat
    eza
    p7zip
    man-db
    rclone
    atuin
    voxtype-onnx
    gh
    yq
    bubblewrap
    ninja
    just
    rustup
    bun
    nodejs
    podman
    fnm
    bitwarden-cli
    dotnet-sdk_9
    yt-dlp
    node-gyp
    gcc
    tree-sitter
    sshfs
    wlr-randr
    grim
    slurp
    swappy
    wl-clipboard
    wtype
    ydotool
    brightnessctl
    pamixer
    nautilus
    btop
    htop
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
