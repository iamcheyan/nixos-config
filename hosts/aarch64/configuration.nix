{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
    ../../modules/keyd.nix
    ../../modules/desktop.nix
    ../../modules/zsh.nix
    ../../modules/cli.nix
    ../../modules/dev.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "aarch64";
  time.timeZone = "Asia/Tokyo";

  home-manager.users.tetsuya = {
    imports = [ inputs.nixarchy.homeManagerModules.nixarchy ];
    home.stateVersion = "26.05";
    programs.nixarchy.enable = true;

    # Keep the user-selected cursor across every Nixarchy theme change.
    xdg.configFile."omarchy/hooks/theme-set.d/cursor".enable = lib.mkForce false;
    home.pointerCursor = {
      gtk.enable = true;
      x11.enable = true;
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };
  };

  services.spice-vdagentd.enable = true;
  services.qemuGuest.enable = true;

  users.users.tetsuya = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "tetsuya";
    extraGroups = [ "networkmanager" "wheel" "audio" "video" ];
  };

  environment.systemPackages = with pkgs; [
    spice-vdagent
  ];

  system.stateVersion = "26.05";
}
