{ pkgs, ... }:

{
  # Development baseline that is useful on both NixOS and macOS. Package
  # names are evaluated for aarch64-darwin by nixpkgs; do not copy Linux-only
  # packages from modules/desktop.nix into this list.
  environment.systemPackages = with pkgs; [
    bat
    btop
    eza
    gnumake
    htop
    python3
    starship
  ];
}
