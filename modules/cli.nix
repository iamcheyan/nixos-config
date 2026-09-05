{ config, pkgs, ... }:

{
  # Cross-host command-line environment.
  # This module intentionally contains no desktop services or compilers.
  environment.systemPackages = with pkgs; [
    git
    chezmoi
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
    tree
    fastfetch
    ranger
    atuin
  ];
}
