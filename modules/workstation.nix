{ config, lib, pkgs, inputs, ... }:

{
  # Shared graphical workstation baseline.  Individual hosts should keep only
  # hardware, hostname, and machine-specific power/virtualization settings.
  imports = [
    ./core.nix
    ./keyd.nix
    ./desktop.nix
    ./labwc.nix
    ./labwc-plus.nix
    ./zsh.nix
    ./cli.nix
    ./dev.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager.extraSpecialArgs = {
    inherit inputs;
    hostName = config.networking.hostName;
  };
  # Preserve pre-existing unmanaged GTK files when Home Manager first takes
  # ownership of them.  This keeps activation recoverable on this workstation.
  # Keep older backups intact; v3 and v4 are already occupied by prior
  # activations on this workstation.
  home-manager.backupFileExtension = "hm-backup-nixos-v5";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  time.timeZone = "Asia/Tokyo";

  home-manager.users.tetsuya = {
    imports = [ ./home-manager/nixos-user.nix ];
    home.sessionVariables.BROWSER = "firefox";
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = [ "firefox.desktop" ];
        "x-scheme-handler/http" = [ "firefox.desktop" ];
        "x-scheme-handler/https" = [ "firefox.desktop" ];
        "x-scheme-handler/about" = [ "firefox.desktop" ];
        "x-scheme-handler/unknown" = [ "firefox.desktop" ];
        "image/png" = [ "org.kde.gwenview.desktop" ];
        "image/jpeg" = [ "org.kde.gwenview.desktop" ];
        "image/webp" = [ "org.kde.gwenview.desktop" ];
        "image/gif" = [ "org.kde.gwenview.desktop" ];
        "image/svg+xml" = [ "org.kde.gwenview.desktop" ];
        "image/tiff" = [ "org.kde.gwenview.desktop" ];
        "application/pdf" = [ "okularApplication_pdf.desktop" ];
        "application/x-7z-compressed" = [ "wind7z.desktop" ];
        "application/zip" = [ "wind7z.desktop" ];
        "application/x-rar-compressed" = [ "wind7z.desktop" ];
        "application/vnd.rar" = [ "wind7z.desktop" ];
        "application/x-xz" = [ "wind7z.desktop" ];
        "application/x-xz-compressed" = [ "wind7z.desktop" ];
        "application/x-bzip" = [ "wind7z.desktop" ];
        "application/x-bzip2" = [ "wind7z.desktop" ];
        "application/gzip" = [ "wind7z.desktop" ];
        "application/x-gzip" = [ "wind7z.desktop" ];
        "application/x-tar" = [ "wind7z.desktop" ];
        "application/x-compressed-tar" = [ "wind7z.desktop" ];
        "inode/directory" = [ "org.kde.dolphin.desktop" ];
      };
      associations.added = {
        "image/png" = [ "org.kde.gwenview.desktop" ];
        "image/jpeg" = [ "org.kde.gwenview.desktop" ];
        "image/webp" = [ "org.kde.gwenview.desktop" ];
        "image/gif" = [ "org.kde.gwenview.desktop" ];
        "image/svg+xml" = [ "org.kde.gwenview.desktop" ];
        "image/tiff" = [ "org.kde.gwenview.desktop" ];
        "application/pdf" = [ "okularApplication_pdf.desktop" ];
        "inode/directory" = [ "org.kde.dolphin.desktop" ];
      };
    };
  };

  users.users.tetsuya = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "tetsuya";
    extraGroups = [ "networkmanager" "wheel" "audio" "video" ];
  };

  environment.systemPackages = with pkgs; [
    android-tools
    spice-vdagent
  ];

  # KDE/KIO's “Open With” dialog looks up this conventional menu name.  The
  # Plasma package only installs plasma-applications.menu on this Hyprland
  # session, so without this compatibility link the chooser can be empty
  # even though the desktop entries and MIME defaults are present.
  environment.etc."xdg/menus/applications.menu".source =
    "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";
}
