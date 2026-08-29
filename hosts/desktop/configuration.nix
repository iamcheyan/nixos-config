{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware.nix                 # Desktop hardware mounts (generate locally on desktop)

    # Shared reusable modules
    ../../modules/core.nix
    ../../modules/desktop.nix
    ../../modules/keyd.nix
    ../../modules/zsh.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager.users.tetsuya = {
    imports = [ inputs.nixarchy.homeManagerModules.nixarchy ];
    home.stateVersion = "26.05";
    programs.nixarchy.enable = true;
  };

  # Host-specific settings
  networking.hostName = "desktop"; # Set host name to desktop
  time.timeZone = "Asia/Tokyo";    # Set timezone for desktop

  # Define user account with Zsh shell
  users.users."tetsuya" = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "tetsuya";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # Graphics/Nvidia driver template for Desktop (uncomment if desktop uses Nvidia GPU)
  # services.xserver.videoDrivers = [ "nvidia" ];
  # hardware.graphics.enable = true;
  # hardware.nvidia = {
  #   modesetting.enable = true;
  #   powerManagement.enable = false;
  #   open = false;
  #   nvidiaSettings = true;
  #   package = config.boot.kernelPackages.nvidiaPackages.stable;
  # };

  # Keep stateVersion matching original installation
  system.stateVersion = "26.05";
}
