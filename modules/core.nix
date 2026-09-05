{ config, pkgs, ... }:

{
  # Settings shared by every NixOS host in this repository.
  # Host hardware, desktop services, development tools, and WSL integration
  # belong in their dedicated modules or host configurations.
  # Every NixOS host gets the dynamic loader for unpatched development binaries.
  programs.nix-ld.enable = true;

  # Provide /bin/bash for FHS compatibility and scripts hardcoding #!/bin/bash
  system.activationScripts.binbash = ''
    mkdir -m 0755 -p /bin
    ln -sfn "${pkgs.bashInteractive}/bin/bash" /bin/bash
  '';

  # Shared remote-access baseline for every host.
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  i18n.defaultLocale = "zh_CN.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
    LC_IDENTIFICATION = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_MONETARY = "ja_JP.UTF-8";
    LC_NAME = "ja_JP.UTF-8";
    LC_NUMERIC = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
    LC_TELEPHONE = "ja_JP.UTF-8";
    LC_TIME = "ja_JP.UTF-8";
  };
}
