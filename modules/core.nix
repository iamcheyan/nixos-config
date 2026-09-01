{ config, ... }:

{
  # Settings shared by every NixOS host in this repository.
  # Host hardware, desktop services, development tools, and WSL integration
  # belong in their dedicated modules or host configurations.
  # Every NixOS host gets the dynamic loader for unpatched development binaries.
  programs.nix-ld.enable = true;

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
