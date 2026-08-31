{ config, pkgs, ... }:

{
  # Compiler, interpreter, and build-tool layer.
  # Keep this separate from cli.nix so a shell-only host can omit it.
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    python3
    gcc
    gnumake
    cmake
  ];
}
