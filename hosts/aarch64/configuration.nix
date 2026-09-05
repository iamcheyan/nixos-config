{ config, lib, pkgs, inputs, localRoot ? "", ... }:

let
  localHost = if localRoot != "" then "${localRoot}/hosts/aarch64.nix" else null;
in
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
  ] ++ lib.optional (localHost != null && builtins.pathExists localHost) localHost;

  home-manager.extraSpecialArgs = { inherit inputs; };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "aarch64";
  time.timeZone = "Asia/Tokyo";

  home-manager.users.tetsuya = {
    imports = [ ../../modules/home-manager/nixos-user.nix ];
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
