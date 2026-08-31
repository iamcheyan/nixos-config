{ config, pkgs, ... }:

{
  imports = [
    ../../modules/core.nix
    ../../modules/zsh.nix
    ../../modules/dev.nix
  ];

  wsl.enable = true;
  wsl.defaultUser = "tetsuya";

  networking.hostName = "nixos-wsl";
  time.timeZone = "Asia/Tokyo";

  # No display manager, desktop, audio, Bluetooth, printing, or SSH daemon.
  # Windows Terminal/WSL provides the terminal and network integration.

  users.users.tetsuya = {
    isNormalUser = true;
    description = "tetsuya";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  system.stateVersion = "26.05";
}
