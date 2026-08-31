{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/core.nix
    ../../modules/zsh.nix
    ../../modules/cli.nix
  ];

  wsl.enable = true;
  wsl.defaultUser = "hkaku";

  # Optional local certificate: create local/zscaler-root-ca.crt after cloning.
  # The ignored file is intentionally user-managed and is never committed.
  security.pki.certificateFiles = lib.optional
    (builtins.pathExists ../../local/zscaler-root-ca.crt)
    ../../local/zscaler-root-ca.crt;

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
