{ config, pkgs, ... }:

{
  imports = [
    ./hardware.nix                 # Laptop hardware mounts and partitions

    # Shared reusable modules
    ../../modules/core.nix
    ../../modules/desktop.nix
    ../../modules/keyd.nix
    ../../modules/zsh.nix
  ];

  # Host-specific settings
  networking.hostName = "laptop";  # Set host name to laptop
  time.timeZone = "Asia/Tokyo";    # Set timezone for laptop

  # Define user account with Zsh shell
  users.users."tetsuya" = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "tetsuya";
    extraGroups = [ "networkmanager" "wheel" ];
    # If using hashed passwords, they can be read from files like:
    # hashedPasswordFile = "/etc/nixos-secrets/tetsuya-password-hash";
  };

  # Keep stateVersion matching original installation
  system.stateVersion = "26.05";
}
