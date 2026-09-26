{ config, lib, pkgs, inputs, ... }:
let
  desktopPackage = pkgs.callPackage ./packages/desktop-compat.nix { };
  tree = "${desktopPackage}/share/omarchy";
  usingFcitx5 = config.i18n.inputMethod.enable && config.i18n.inputMethod.type == "fcitx5";
  sessionLauncher = pkgs.writeShellScript "desktop-hyprland-session" ''
    export OMARCHY_PATH=${tree}
    exec ${pkgs.uwsm}/bin/uwsm start -N "Hyprland (local)" -D Hyprland -- \
      ${config.programs.hyprland.package}/bin/start-hyprland -- --config ${tree}/config/hypr/hyprland.lua
  '';
  session = (pkgs.writeTextFile {
    name = "local-hyprland-session";
    destination = "/share/wayland-sessions/omarchy.desktop";
    text = ''
      [Desktop Entry]
      Name=Hyprland (local)
      Comment=Locally managed Hyprland compatibility session
      Exec=${sessionLauncher}
      Type=Application
      DesktopNames=Hyprland
    '';
  }).overrideAttrs (_: { passthru.providedSessions = [ "omarchy" ]; });
in {
  imports = [ inputs.hyprland.nixosModules.default ];
  nix.settings = {
    experimental-features = lib.mkDefault [ "nix-command" "flakes" ];
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE=" ];
  };
  programs.git = { enable = lib.mkDefault true; config.safe.directory = [ "/home/tetsuya/nixos-config" ]; };
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    withUWSM = true;
  };
  programs.nix-ld.enable = lib.mkDefault true;
  programs.bash.interactiveShellInit = "source ${tree}/default/bash/rc";
  programs.zsh.interactiveShellInit = lib.mkIf config.programs.zsh.enable "source ${tree}/default/zsh/rc";
  programs.fish.interactiveShellInit = lib.mkIf config.programs.fish.enable "source ${tree}/default/fish/rc";
  environment.sessionVariables = {
    OMARCHY_PATH = tree;
    OMARCHY_SCREENSHOT_EDITOR = lib.mkDefault "satty-edit";
    NIXOS_CONFIG = "/home/tetsuya/nixos-config";
    XDG_DATA_DIRS = [ "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" ];
  };
  environment.systemPackages = [ desktopPackage session ] ++ (with pkgs; [
    bash coreutils util-linux fontconfig findutils gnused gnugrep gawk jq gum curl socat systemd glib xdg-utils libnotify
    hyprpicker hyprsunset hyprlock quickshell wl-clipboard wtype grim slurp
    imagemagick ffmpeg gpu-screen-recorder mpv yt-dlp tesseract zbar qrencode pciutils brightnessctl ddcutil
    pulseaudio wireplumber playerctl bluez networkmanager fastfetch nh btop ripgrep fd dua bat fzf tmux inotify-tools python3
    xdg-terminal-exec uwsm foot chromium nautilus neovim mise lazygit lazydocker eza zoxide starship gtk3 udiskie git less man-db
    unzip pamixer alsa-utils imv evince tldr inxi ffmpegthumbnailer vips file libxkbcommon xdg-user-dirs satty wl-screenrec
    (pkgs.callPackage ./packages/ttfx.nix { })
    gsettings-desktop-schemas gnome-themes-extra yaru-theme adwaita-icon-theme hyprland-preview-share-picker bibata-cursors
    pinta libreoffice xournalpp obs-studio moonlight-qt kdePackages.kdenlive gnome-disk-utility sushi cliamp
  ]);
  services = {
    locate.enable = lib.mkDefault true;
    printing.browsed.enable = lib.mkDefault false;
    avahi = { enable = lib.mkDefault true; nssmdns4 = lib.mkDefault true; openFirewall = lib.mkDefault true; };
    gvfs.enable = lib.mkDefault true;
    udisks2.enable = lib.mkDefault true;
    upower.enable = lib.mkDefault true;
    pipewire.jack.enable = lib.mkDefault true;
    logind.settings.Login = { HandlePowerKey = lib.mkDefault "ignore"; InhibitDelayMaxSec = lib.mkDefault 15; };
    displayManager.sessionPackages = [ session ];
  };
  environment.etc."omarchy/xcompose".source = "${tree}/default/xcompose";
  virtualisation.docker.enable = lib.mkDefault true;
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];
  security.pam.services = { omarchy-lock-password = { }; }
    // lib.optionalAttrs config.services.fprintd.enable { omarchy-lock-fingerprint.unixAuth = false; };
  systemd = {
      user.services = {
        bt-agent = {
          description = "Bluetooth pairing agent (auto-accept)";
          documentation = [ "man:bt-agent(1)" ];
          unitConfig.ConditionPathIsDirectory = "/sys/class/bluetooth";
          after = [ "dbus.socket" ];
          requires = [ "dbus.socket" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "simple";
            ExecCondition = "${config.systemd.package}/bin/systemctl is-active --quiet bluetooth.service";
            ExecStart = "${pkgs.bluez-tools}/bin/bt-agent -c NoInputNoOutput";
            Restart = "on-failure";
            RestartSec = 2;
          };
        };

        omarchy-sleep-lock = {
          description = "Lock Omarchy before suspend";
          after = [
            "dbus.socket"
            "wayland-session-waitenv.service"
          ];
          requires = [ "dbus.socket" ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          path = [ "/run/current-system/sw" ];
          unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
          environment.OMARCHY_PATH = tree;
          serviceConfig = {
            Type = "simple";
            ExecStart = "${desktopPackage}/bin/omarchy-system-sleep-monitor";
            Restart = "always";
            RestartSec = 2;
          };
        };

        omarchy-crash-watch = {
          description = "Announce process crashes and offer an AI diagnosis";
          after = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          path = [ "/run/current-system/sw" ];
          unitConfig = {
            ConditionEnvironment = "WAYLAND_DISPLAY";
            ConditionPathExists = "!%h/.local/state/omarchy/toggles/crash-capture-off";
          };
          serviceConfig = {
            Type = "simple";
            ExecStart = "${desktopPackage}/bin/omarchy-crash-watch";
            Restart = "always";
            RestartSec = 5;
          };
        };

        omarchy-recover-internal-monitor = {
          description = "Recover the internal monitor toggle when no external display is connected";
          before = [ "graphical-session-pre.target" ];
          wantedBy = [ "graphical-session-pre.target" ];
          path = [ "/run/current-system/sw" ];
          unitConfig.ConditionPathExists = "%h/.local/state/omarchy/toggles/hypr/internal-monitor-disable.lua";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${desktopPackage}/bin/omarchy-hw-recover-internal-monitor";
          };
        };
      }
      // lib.optionalAttrs usingFcitx5 {
        omarchy-fcitx5 = {
          description = "Fcitx5 input method (XCompose sequences)";
          after = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
          serviceConfig = {
            Type = "simple";
            ExecStart = "${config.i18n.inputMethod.package}/bin/fcitx5 --disable notificationitem";
            Restart = "always";
            RestartSec = 2;
          };
        };
      };

      user.units."app.slice" = {
        overrideStrategy = "asDropin";
        text = ''
          [Slice]
          ManagedOOMMemoryPressure=kill
          ManagedOOMSwap=kill
        '';
      };
    };
  hardware.i2c.enable = lib.mkDefault true;
  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  boot.plymouth = { enable = lib.mkDefault true; theme = lib.mkDefault "omarchy"; themePackages = lib.mkDefault [ desktopPackage ]; };
  fonts.fontconfig.localConf = lib.mkDefault (builtins.readFile ./anchor-shell/compat/omarchy/default/fontconfig/conf.avail/50-omarchy.conf);
  fonts.packages = [ desktopPackage ] ++ (with pkgs; [ noto-fonts noto-fonts-cjk-sans noto-fonts-color-emoji nerd-fonts.jetbrains-mono font-awesome liberation_ttf ]);
  xdg.portal = { enable = lib.mkDefault true; extraPortals = [ pkgs.xdg-desktop-portal-gtk ]; };
}
