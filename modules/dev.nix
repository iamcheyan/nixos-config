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
    pkg-config
    tree-sitter

    # Languages & Runtimes
    python3
    nodejs
    fnm
    bun
    rustup
    rustc
    cargo
    # QML/Quickshell plugin development and CI checks.
    qt6Packages.qtbase
    qt6Packages.qtdeclarative
    qt6Packages.qtshadertools
    qt6Packages.qt5compat
    # GTK applications and native dialogs need the compiled GSettings schemas.
    gtk3
    gsettings-desktop-schemas
    libglvnd
    libglvnd.dev
    vulkan-headers
    vulkan-loader
  ];
}
