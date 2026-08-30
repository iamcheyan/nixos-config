{ config, pkgs, ... }:

{
  # 1. Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 2. Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # 3. Networking
  networking.networkmanager.enable = true;

  # Keep this workstation awake during long builds and remote sessions.
  services.logind.settings.Login = {
    IdleAction = "ignore";
  };

  # 4. Select internationalisation properties
  i18n.defaultLocale = "zh_CN.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
    LC_IDENTIFICATION = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_MONETARY = "ja_JP.UTF-8";
    LC_NAME = "ja_JP.UTF-8";
    LC_NUMERIC = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
    LC_TELEPHONE = "ja_JP.UTF-8";
    LC_TIME = "ja_JP.UTF-8";
  };

  # Fcitx5 / Rime Chinese input method
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    # Use the Wayland input-method protocol instead of the legacy
    # GTK_IM_MODULE path. The module then stops exporting
    # GTK_IM_MODULE="fcitx", which is exactly what fcitx5's startup
    # "Wayland 诊断" notification nags about. GTK apps reach fcitx5 via
    # text-input; Qt/SDL still get their explicit IM module below.
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-rime
      fcitx5-gtk
      qt6Packages.fcitx5-configtool
    ];
  };

  environment.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
    # GTK_IM_MODULE intentionally unset: on Wayland the text-input-v2/v3
    # protocol is the preferred input path and fcitx5's own startup
    # diagnostic nags about the legacy GTK IM module. GTK3/GTK4 apps still
    # reach fcitx5 through the portal/protocol; X11/XWayland GTK apps are
    # covered by XMODIFIERS above.
    QT_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
  };

  # Passwordless sudo for the primary user (single-user workstation).
  security.sudo.extraRules = [
    {
      users = [ "tetsuya" ];
      commands = [ { command = "ALL"; options = [ "NOPASSWD" "SETENV" ]; } ];
    }
  ];

  # 6. Basic utilities and settings
  services.printing.enable = true;
  services.openssh.enable = true;

  # NixOS owns the package, generated /etc/keyd configuration and daemon.
  services.keyd = {
    enable = true;
    keyboards.minila-r-convertible = {
      ids = [ "k:0c45:22b8" ];
      settings.main = {
        leftalt = "leftmeta";
        leftmeta = "leftalt";
        muhenkan = "f13";
        katakanahiragana = "left";
        delete = "right";
        rightcontrol = "up";
        rightalt = "down";
        grave = "escape";
        escape = "grave";
      };
    };
  };

  # Nix-ld loader to run unpatched dynamic binaries
  programs.nix-ld.enable = true;

  # Enable Firefox
  programs.firefox.enable = true;

  # Allow unfree licensing
  nixpkgs.config.allowUnfree = true;

  # 7. Core packages needed everywhere
  # Base tools mirrored from the chezmoi cross-platform installer.
  # NixOS owns these packages; chezmoi keeps equivalent branches for
  # macOS, Arch and Debian.
  environment.systemPackages = with pkgs; [
    zsh git curl wget openssh tmux neovim
    ripgrep fd fzf jq bat eza starship age
    unzip zip p7zip man-db
    kitty alacritty ghostty foot yazi zellij ranger firefox
    voxtype-onnx gh yq cmake ninja just rustup bun nodejs rclone podman atuin
    fish fontconfig python3 python3Packages.pip fnm
    bitwarden-cli dotnet-sdk_9 yt-dlp node-gyp gcc gnumake tree-sitter sshfs
  ];

  # 8. zram: compress cold pages in RAM instead of hitting the NVMe swap
  # partition. Without it the system swaps 3+ GB to disk on a 14G machine and
  # refaulting those pages causes half-second stalls when switching back to
  # idle windows. Disk swap stays as spill (zram wins on priority).
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50; # ~7G of compressible cold pages
    priority = 100; # above the NVMe partition's -1
  };

  # zram tuning: prefer swapping to compressed RAM over dropping file cache.
  # (vm.page_cluster does not exist on this kernel — 7.x dropped it.)
  boot.kernel.sysctl."vm.swappiness" = 180;
}
