{ config, pkgs, ... }:

{
  # Cross-platform compiler, interpreter, and build-tool layer shared by NixOS and macOS.
  # Keep this separate from cli.nix so a minimal shell-only host can omit it.
  environment.systemPackages = with pkgs; [
    # GitHub CLI
    gh

    # Build tools & Task runners
    just
    gnumake
    cmake
    ninja
    tree-sitter

    # Languages & Runtimes
    python3
    nodejs
    fnm
    bun
    rustup
  ];
}
