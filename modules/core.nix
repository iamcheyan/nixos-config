{ config, pkgs, ... }:

{
  # 1. Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 2. Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # 3. Networking
  networking.networkmanager.enable = true;

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
    fcitx5.addons = with pkgs; [
      fcitx5-rime
      fcitx5-gtk
      qt6Packages.fcitx5-configtool
    ];
  };

  environment.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
  };

  # 6. Basic utilities and settings
  services.printing.enable = true;
  services.openssh.enable = true;

  # Nix-ld loader to run unpatched dynamic binaries
  programs.nix-ld.enable = true;

  # Enable Firefox
  programs.firefox.enable = true;

  # Allow unfree licensing
  nixpkgs.config.allowUnfree = true;

  # 7. Core packages needed everywhere
  environment.systemPackages = with pkgs; [
    jq
    curl
    git
    ripgrep
    fish
    fontconfig
    unzip
    python3
    python3Packages.pip
    fnm
  ];
}
