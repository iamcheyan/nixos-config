{ config, pkgs, ... }:

{
  # Cross-platform command-line environment shared by NixOS and macOS (nix-darwin).
  # This module intentionally contains no desktop services or compiler toolchains.
  environment.systemPackages = with pkgs; [
    # Core & Shell utilities
    git
    chezmoi
    curl
    wget
    openssh
    ffmpeg
    git-extras
    translate-shell
    tmux
    zellij
    neovim
    fresh-editor

    # Modern CLI replacements & search
    ripgrep
    fd
    fzf
    jq
    yq
    bat
    eza
    zoxide
    glow
    mdcat
    tealdeer
    gping
    httpie
    broot
    viu
    tree
    fastfetch

    # Archiving & file management
    yazi
    ranger
    zip
    unzip
    p7zip

    # Productivity & sync
    age
    atuin
    starship
    rclone
    yt-dlp
    bitwarden-cli

    # Monitoring
    btop
    htop
  ];
}
