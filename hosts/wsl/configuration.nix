{ config, lib, pkgs, ... }:

let
  localHost = ../../local/hosts/wsl.nix;
in
{
  imports = [
    ../../modules/core.nix
    ../../modules/zsh.nix
    ../../modules/cli.nix
  ] ++ lib.optional (builtins.pathExists localHost) localHost;

  wsl.enable = true;
  wsl.defaultUser = "hkaku";

  networking.hostName = "nixos-wsl";
  time.timeZone = "Asia/Tokyo";

  # No display manager, desktop, audio, Bluetooth, printing, or SSH daemon.
  # Windows Terminal/WSL provides the terminal and network integration.

  users.users.hkaku = {
    isNormalUser = true;
    description = "hkaku";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  system.stateVersion = "26.05";
}
