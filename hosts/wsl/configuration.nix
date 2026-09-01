{ config, lib, pkgs, localRoot ? "", ... }:

let
  localHost = if localRoot != "" then "${localRoot}/hosts/wsl.nix" else null;
in
{
  imports = [
    ../../modules/core.nix
    ../../modules/zsh.nix
    ../../modules/cli.nix
  ] ++ lib.optional (localHost != null && builtins.pathExists localHost) localHost;

  wsl.enable = true;
  wsl.defaultUser = "hkaku";

  networking.hostName = "nixos-wsl";
  time.timeZone = "Asia/Tokyo";

  # No display manager, desktop, audio, Bluetooth, or printing.
  # Windows Terminal/WSL provides the terminal and network integration; SSH is
  # enabled by the shared core module.

  users.users.hkaku = {
    isNormalUser = true;
    description = "hkaku";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  system.stateVersion = "26.05";
}
