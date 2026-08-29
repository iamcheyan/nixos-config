{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core.nix
    ../../modules/zsh.nix
  ];

  networking.hostName = "nixos-aarch64";
  time.timeZone = "Asia/Tokyo";

  # This machine currently runs the stock GNOME desktop. Keep the ARM host
  # independent from the legacy OMD/Sumika session module.
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

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
