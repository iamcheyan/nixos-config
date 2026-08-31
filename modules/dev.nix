{ config, pkgs, ... }:

{
  # Minimal cross-host development baseline.
  # Desktop applications and WSL integration stay outside this module.
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    openssh
    tmux
    neovim
    ripgrep
    fd
    fzf
    jq
    unzip
    zip
    python3
    gcc
    gnumake
    cmake
  ];
}
