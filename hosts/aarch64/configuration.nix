{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
    ../../modules/desktop.nix
    ../../modules/zsh.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  networking.hostName = "aarch64";
  time.timeZone = "Asia/Tokyo";

  home-manager.users.tetsuya = {
    imports = [ inputs.nixarchy.homeManagerModules.nixarchy ];
    home.stateVersion = "26.05";
    programs.nixarchy.enable = true;
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
