{ config, pkgs, ... }:

{
  # NixOS-WSL provides the WSL2 integration; keep this host intentionally
  # separate from the desktop-oriented hosts in this flake.
  wsl.enable = true;
  wsl.defaultUser = "tetsuya";

  networking.hostName = "nixos-wsl";
  time.timeZone = "Asia/Tokyo";

  # No display manager, desktop, audio, Bluetooth, printing, or SSH daemon.
  # Windows Terminal/WSL provides the terminal and network integration.
  programs.zsh.enable = true;

  users.users.tetsuya = {
    isNormalUser = true;
    description = "tetsuya";
    shell = pkgs.zsh;
  };

  # Minimal terminal and development baseline for WSL2.
  environment.systemPackages = with pkgs; [
    zsh
    tmux
    git
    curl
    wget
    openssh
    ripgrep
    fd
    fzf
    jq
    unzip
    zip
    neovim
    python3
    gcc
    gnumake
    cmake
  ];

  system.stateVersion = "26.05";
}
